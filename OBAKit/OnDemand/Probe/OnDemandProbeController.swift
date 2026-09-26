//
//  OnDemandProbeController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import CoreLocation
import Foundation
import OBAKitCore

/// Owns the point-mode probe (spec 2.1): its two caches, its error rules and
/// the deployment it belongs to. Both map shells share one instance per
/// screen; surfaces read its published state and never probe on their own.
///
/// The rider/centre cache is keyed per `(deployment, point rounded to 3
/// decimals)`; the address check and planner use `probeExact`, keyed to 5
/// decimals, and never read the other cache.
@MainActor
final class OnDemandProbeController: NSObject, ObservableObject {

    struct Configuration {
        var radiusMeters = 5_000.0
        var cacheLifetime: TimeInterval = 600
        var movementThresholdMeters = 100.0
        var accuracyGateMeters = 100.0
        var probeKeyDecimals = 3
        var exactKeyDecimals = 5
    }

    enum ProbeError: Error {
        case noAPIService
        /// The deployment is known to lack `/api/ondemand`.
        case unsupported
    }

    let configuration: Configuration
    private let apiService: () -> RESTAPIService?
    private let geometryCache: OnDemandGeometryCache
    let now: () -> Date

    private struct CacheKey: Hashable {
        let deployment: String
        let latitude: Double
        let longitude: Double
    }

    private struct CacheEntry {
        let services: [OnDemandService]
        let fetchedAt: Date
    }

    /// A 3-decimal rider key and a 5-decimal exact key can be equal (38.8001
    /// rounds to 38.8; 38.8 stays 38.8), so in-flight tasks are keyed by kind
    /// too: an exact probe never joins a rider probe (spec 2.1).
    private struct InFlightKey: Hashable {
        let isExact: Bool
        let cacheKey: CacheKey
    }

    private var probeCache: [CacheKey: CacheEntry] = [:]
    private var exactCache: [CacheKey: CacheEntry] = [:]
    private var inFlight: [InFlightKey: Task<[OnDemandService], Error>] = [:]

    /// The key `OnDemandSupport` uses: the REST base URL of the current region.
    private(set) var currentDeployment: String?
    private(set) var isUnsupported = false

    init(
        apiService: @escaping () -> RESTAPIService?,
        geometryCache: OnDemandGeometryCache,
        now: @escaping () -> Date = Date.init,
        configuration: Configuration = Configuration()
    ) {
        self.apiService = apiService
        self.geometryCache = geometryCache
        self.now = now
        self.configuration = configuration
        super.init()
        currentDeployment = deployment
        isUnsupported = Self.isKnownUnsupported(apiService())
    }

    var deployment: String? { apiService()?.baseURL.absoluteString }

    // MARK: - Probes

    /// The rider/centre probe. `allowStale` reuses an expired entry without a
    /// network call (trigger 4 in spec 2.1).
    func probe(at coordinate: CLLocationCoordinate2D, allowStale: Bool = false) async throws -> [OnDemandServiceMatch] {
        let services = try await services(at: coordinate, decimals: configuration.probeKeyDecimals, exact: false, allowStale: allowStale)
        return OnDemandServiceMatch.matches(from: services, now: now())
    }

    /// The exact-coordinate probe for the address check and the planner.
    func probeExact(at coordinate: CLLocationCoordinate2D) async throws -> [OnDemandServiceMatch] {
        let services = try await services(at: coordinate, decimals: configuration.exactKeyDecimals, exact: true, allowStale: false)
        return OnDemandServiceMatch.matches(from: services, now: now())
    }

    /// Full geometry for a matched service, cached per `(deployment, serviceId)`.
    func fullAreas(for serviceID: String) async throws -> [ServiceArea] {
        guard let apiService = apiService() else { throw ProbeError.noAPIService }
        return try await geometryCache.areas(deployment: apiService.baseURL.absoluteString, serviceID: serviceID, apiService: apiService)
    }

    /// Region switch or custom URL change: cancels in-flight probes and
    /// geometry fetches, drops both probe caches and forgets the old
    /// deployment's support state.
    func deploymentDidChange() {
        resetState(for: deployment)
    }

    static func cacheKey(for coordinate: CLLocationCoordinate2D, decimals: Int) -> (latitude: Double, longitude: Double) {
        let scale = pow(10.0, Double(decimals))
        return ((coordinate.latitude * scale).rounded() / scale, (coordinate.longitude * scale).rounded() / scale)
    }

    // MARK: - Fetching

    private func services(at coordinate: CLLocationCoordinate2D, decimals: Int, exact: Bool, allowStale: Bool) async throws -> [OnDemandService] {
        guard let apiService = apiService() else { throw ProbeError.noAPIService }
        let deployment = apiService.baseURL.absoluteString
        if deployment != currentDeployment {
            resetState(for: deployment)
        }
        if isUnsupported || Self.isKnownUnsupported(apiService) {
            isUnsupported = true
            throw ProbeError.unsupported
        }

        let rounded = Self.cacheKey(for: coordinate, decimals: decimals)
        let key = CacheKey(deployment: deployment, latitude: rounded.latitude, longitude: rounded.longitude)
        if let entry = exact ? exactCache[key] : probeCache[key],
           allowStale || now().timeIntervalSince(entry.fetchedAt) < configuration.cacheLifetime {
            return entry.services
        }
        let inFlightKey = InFlightKey(isExact: exact, cacheKey: key)
        if let task = inFlight[inFlightKey] {
            return try await task.value
        }

        let radius = configuration.radiusMeters
        let task = Task { try await apiService.getOnDemandServices(near: coordinate, radiusMeters: radius, geometryDetail: .none).list }
        inFlight[inFlightKey] = task
        defer {
            // A deployment reset may have let a newer probe take this key meanwhile.
            if inFlight[inFlightKey] == task { inFlight[inFlightKey] = nil }
        }

        // `getOnDemandServices(near:)` records a 404 in `onDemandSupport`
        // itself; any other failure is transient: rethrown, nothing cached.
        do {
            let services = try await task.value
            // A result for a deployment that is no longer current is discarded.
            guard deployment == currentDeployment else { throw CancellationError() }
            let entry = CacheEntry(services: services, fetchedAt: now())
            if exact {
                exactCache[key] = entry
            } else {
                probeCache[key] = entry
            }
            return services
        } catch let error as APIError {
            if case .requestNotFound = error, deployment == currentDeployment {
                isUnsupported = true
            }
            throw error
        }
    }

    private func resetState(for deployment: String?) {
        cancelInFlight()
        probeCache = [:]
        exactCache = [:]
        currentDeployment = deployment
        isUnsupported = Self.isKnownUnsupported(apiService())
    }

    private func cancelInFlight() {
        for task in inFlight.values {
            task.cancel()
        }
        inFlight = [:]
        let geometryCache = geometryCache
        Task { await geometryCache.cancelAll() }
    }

    private static func isKnownUnsupported(_ apiService: RESTAPIService?) -> Bool {
        guard let apiService else { return false }
        return apiService.onDemandSupport.isKnownUnsupported(baseURL: apiService.baseURL)
    }
}
