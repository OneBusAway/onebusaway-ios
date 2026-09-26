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
import UIKit

/// What the dock slot shows (spec 2.4). Never two things at once.
enum OnDemandDockState: Equatable {
    case hidden
    /// Region level, probe point inside these (sorted) services.
    case card([OnDemandServiceMatch])
    /// Street level: the inside stack, or the nearby stack when none is inside.
    case bar([OnDemandServiceMatch])
    /// The planner showed an empty result; R11 over R5.
    case planner(OnDemandPlannerResult)

    var isBar: Bool {
        if case .bar = self { return true }
        return false
    }
}

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

    // MARK: - Dock state

    @Published private(set) var dockState: OnDemandDockState = .hidden
    @Published private(set) var matches: [OnDemandServiceMatch] = []
    @Published private(set) var probePoint: CLLocationCoordinate2D?
    @Published private(set) var probeSource: ProbeSource = .mapCenter
    @Published private(set) var zoomLevel: OnDemandZoomLevel = .hidden
    /// Full geometry per matched service as it arrives (spec 2.7).
    @Published private(set) var fullAreasByServiceID: [String: [ServiceArea]] = [:]
    /// Services whose geometry fetch failed; the thumbnail stays a placeholder for them.
    @Published private(set) var failedGeometryServiceIDs: Set<String> = []
    /// The resolved edge per match: the server point outside, the client geometry inside.
    @Published private(set) var edgesByServiceID: [String: OnDemandEdge] = [:]
    /// Spec 2.3: set by a bar page swipe or picker row; cleared when the dock leaves the bar.
    @Published var highlightedServiceID: String?

    private(set) var refreshTask: Task<Void, Never>?
    private(set) var geometryTask: Task<Void, Never>?
    private(set) var boundaryTask: Task<Void, Never>?

    private let isLocationAuthorized: () -> Bool
    private let currentLocation: () -> CLLocation?
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    private var mapCenter: CLLocationCoordinate2D?
    private var riderLocation: CLLocation?
    private var lastProbePoint: CLLocationCoordinate2D?
    private var lastSuccessfulProbePoint: CLLocationCoordinate2D?
    private(set) var isLayerEnabled = true
    private var hasSurfaceFocus = false
    private var isMapMostlyCovered = false
    /// Shown until `clearPlanner()`; routine reprobes never replace it.
    private var activePlannerResult: OnDemandPlannerResult?

    private enum RefreshReason {
        case mapSettled, locationUpdate, authorization, foreground, boundary

        /// Authorization, foreground and boundary probes ignore the 100 m rule.
        var ignoresMovementThreshold: Bool { self != .mapSettled && self != .locationUpdate }
    }

    /// The current probe point's location facts for a detail page opened from the dock.
    var locationCheck: OnDemandLocationCheck? {
        guard let probePoint else { return nil }
        return OnDemandLocationCheck(source: probeSource, isInside: matches.contains(where: \.isInside), locality: nil, coordinate: probePoint)
    }

    /// The current probe point's facts for one service, for a detail page
    /// opened from that service's region pin (spec 3.6 item 3); nil when the
    /// service is not in the match list, so the page omits the location row.
    func locationCheck(forServiceID serviceID: String) -> OnDemandLocationCheck? {
        guard let probePoint, let match = matches.first(where: { $0.id == serviceID }) else { return nil }
        return OnDemandLocationCheck(source: probeSource, isInside: match.isInside, locality: nil, coordinate: probePoint)
    }

    init(
        apiService: @escaping () -> RESTAPIService?,
        geometryCache: OnDemandGeometryCache,
        now: @escaping () -> Date = Date.init,
        configuration: Configuration = Configuration(),
        isLocationAuthorized: @escaping () -> Bool = { false },
        currentLocation: @escaping () -> CLLocation? = { nil },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.apiService = apiService
        self.geometryCache = geometryCache
        self.now = now
        self.configuration = configuration
        self.isLocationAuthorized = isLocationAuthorized
        self.currentLocation = currentLocation
        self.sleep = sleep
        super.init()
        currentDeployment = deployment
        isUnsupported = Self.isKnownUnsupported(apiService())
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    isolated deinit {
        refreshTask?.cancel()
        geometryTask?.cancel()
        boundaryTask?.cancel()
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
        let deployment = apiService.baseURL.absoluteString
        let areas = try await geometryCache.areas(deployment: deployment, serviceID: serviceID, apiService: apiService)
        // The reset's `cancelAll()` is not awaited, so an old fetch can still land.
        try discardUnlessCurrent(deployment)
        return areas
    }

    /// What a service page opened from the dock, bar or picker draws: the
    /// full areas already loaded for `serviceID`, else a fetch through the
    /// same cache.
    func detailGeometry(forServiceID serviceID: String) -> OnDemandDetailGeometry {
        OnDemandDetailGeometry(cached: fullAreasByServiceID[serviceID]) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await fullAreas(for: serviceID)
        }
    }

    /// Region switch or custom URL change: cancels in-flight probes and
    /// geometry fetches, drops both probe caches and forgets the old
    /// deployment's support state.
    func deploymentDidChange() {
        resetState(for: deployment)
        refreshTask?.cancel()
        geometryTask?.cancel()
        boundaryTask?.cancel()
        matches = []
        fullAreasByServiceID = [:]
        failedGeometryServiceIDs = []
        edgesByServiceID = [:]
        lastProbePoint = nil
        lastSuccessfulProbePoint = nil
        highlightedServiceID = nil
        activePlannerResult = nil
        setDockState(.hidden)
    }

    static func cacheKey(for coordinate: CLLocationCoordinate2D, decimals: Int) -> (latitude: Double, longitude: Double) {
        let scale = pow(10.0, Double(decimals))
        return ((coordinate.latitude * scale).rounded() / scale, (coordinate.longitude * scale).rounded() / scale)
    }

    // MARK: - Triggers (spec 2.1)

    /// Trigger 1: the map settled.
    func mapDidSettle(center: CLLocationCoordinate2D, zoomLevel: OnDemandZoomLevel) {
        mapCenter = center
        if zoomLevel != self.zoomLevel {
            highlightedServiceID = nil
            self.zoomLevel = zoomLevel
        }
        refresh(reason: .mapSettled)
    }

    /// Trigger 2.
    func locationAuthorizationDidChange() {
        refresh(reason: .authorization)
    }

    /// Trigger 3.
    func applicationWillEnterForeground() {
        refresh(reason: .foreground)
    }

    @objc private func willEnterForeground() {
        applicationWillEnterForeground()
    }

    /// Trigger 5: a fix worse than 100 m is ignored; the first usable fix
    /// switches the source from the map centre to the rider and probes.
    func locationDidUpdate(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= configuration.accuracyGateMeters else { return }
        let isFirstFix = riderLocation == nil
        riderLocation = location
        guard isLocationAuthorized() else { return }
        refresh(reason: isFirstFix ? .authorization : .locationUpdate)
    }

    func setLayerEnabled(_ enabled: Bool) {
        isLayerEnabled = enabled
        deriveDockState()
    }

    /// A stop, route, trip or directions sheet, search results, or the survey card owns the slot.
    func setSurfaceFocus(_ hasFocus: Bool) {
        hasSurfaceFocus = hasFocus
        deriveDockState()
    }

    /// The bottom sheet leaves less than half the screen to the map.
    func setMapMostlyCovered(_ covered: Bool) {
        isMapMostlyCovered = covered
        deriveDockState()
    }

    // MARK: - Refresh

    private func resolvedProbePoint() -> (coordinate: CLLocationCoordinate2D, source: ProbeSource)? {
        if isLocationAuthorized(), let fix = riderLocation ?? currentLocation() {
            return (fix.coordinate, .rider)
        }
        return mapCenter.map { ($0, .mapCenter) }
    }

    private func refresh(reason: RefreshReason) {
        guard !isUnsupported, let point = resolvedProbePoint() else {
            deriveDockState()
            return
        }
        probeSource = point.source
        if !reason.ignoresMovementThreshold, let lastProbePoint,
           Self.distanceMeters(lastProbePoint, point.coordinate) < configuration.movementThresholdMeters {
            deriveDockState()
            return
        }

        refreshTask?.cancel()
        let allowStale = reason == .boundary
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let matches = try await probe(at: point.coordinate, allowStale: allowStale)
                guard !Task.isCancelled else { return }
                didProbe(point, matches: matches)
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                lastProbePoint = point.coordinate
                handleProbeFailure(at: point.coordinate)
            }
        }
    }

    private func didProbe(_ point: (coordinate: CLLocationCoordinate2D, source: ProbeSource), matches: [OnDemandServiceMatch]) {
        lastProbePoint = point.coordinate
        lastSuccessfulProbePoint = point.coordinate
        probePoint = point.coordinate
        probeSource = point.source
        self.matches = matches
        updateEdges()
        deriveDockState()
        loadGeometry(for: matches)
    }

    /// Spec 2.1: any error other than a 404 keeps the last state only when
    /// the new probe point is within 100 m of the one that produced it.
    private func handleProbeFailure(at coordinate: CLLocationCoordinate2D) {
        if isUnsupported {
            matches = []
            setDockState(.hidden)
            return
        }
        if let lastSuccessfulProbePoint,
           Self.distanceMeters(lastSuccessfulProbePoint, coordinate) <= configuration.movementThresholdMeters {
            deriveDockState()
            return
        }
        matches = []
        edgesByServiceID = [:]
        // Derived rather than set, so a planner card outlives the failure.
        deriveDockState()
    }

    // MARK: - Planner fallback (spec 3.8)

    /// Probes both ends through the exact cache. Nil when either probe fails.
    func plannerResult(origin: CLLocationCoordinate2D, destination: CLLocationCoordinate2D) async -> OnDemandPlannerResult? {
        guard !isUnsupported else { return nil }
        do {
            let originMatches = try await probeExact(at: origin)
            let destinationMatches = try await probeExact(at: destination)
            return OnDemandPlannerQualifier.result(origin: originMatches, destination: destinationMatches, originCoordinate: origin, destinationCoordinate: destination)
        } catch {
            return nil
        }
    }

    func showPlanner(_ result: OnDemandPlannerResult) {
        activePlannerResult = result
        deriveDockState()
    }

    func clearPlanner() {
        guard activePlannerResult != nil else { return }
        activePlannerResult = nil
        deriveDockState()
    }

    // MARK: - Dock state (spec 2.4)

    private func deriveDockState() {
        if let activePlannerResult, !isUnsupported {
            setDockState(.planner(activePlannerResult))
            return
        }
        let slotAvailable = isLayerEnabled && !hasSurfaceFocus && !isMapMostlyCovered && !isUnsupported
        guard slotAvailable else {
            setDockState(.hidden)
            return
        }
        // A match with no area (a pure stop group) has no distance and is never shown.
        let inside = sortedSoonestUsable(matches.filter { $0.isInside && $0.distanceToArea != nil })
        switch zoomLevel {
        case .hidden:
            setDockState(.hidden)
        case .region:
            setDockState(inside.isEmpty ? .hidden : .card(inside))
        case .street:
            if !inside.isEmpty {
                setDockState(.bar(inside))
            } else {
                let nearby = sortedSoonestUsable(matches.filter(\.isNearby))
                setDockState(nearby.isEmpty ? .hidden : .bar(nearby))
            }
        }
    }

    private func setDockState(_ state: OnDemandDockState) {
        // Spec 2.3: only a real exit from the bar drops the highlight, so one
        // set by the picker or held for the detail page while the dock is
        // suppressed survives unrelated refreshes.
        if case .bar = dockState, !state.isBar {
            highlightedServiceID = nil
        }
        if state != dockState {
            dockState = state
        }
        scheduleBoundaryRefresh()
    }

    /// Trigger 4: re-evaluate one second after the earliest `nextChangeInstant`.
    private func scheduleBoundaryRefresh() {
        boundaryTask?.cancel()
        boundaryTask = nil
        guard let nextChange = matches.compactMap(\.availability.nextChangeInstant).min() else { return }
        let delay = max(nextChange.timeIntervalSince(now()), 0) + 1
        let sleep = sleep
        boundaryTask = Task { [weak self] in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.refresh(reason: .boundary)
        }
    }

    // MARK: - Edges and geometry (spec 2.7)

    private func updateEdges() {
        guard let probePoint else {
            edgesByServiceID = [:]
            return
        }
        var edges: [String: OnDemandEdge] = [:]
        for match in matches {
            if !match.isInside, let distance = match.distanceToArea, let point = match.nearestPointOnBoundary {
                edges[match.id] = OnDemandGeometry.edge(from: probePoint, toServerPoint: point, distanceMeters: distance)
            } else if let areas = fullAreasByServiceID[match.id],
                      let edge = OnDemandGeometry.nearestBoundaryPoint(from: probePoint, areas: areas) {
                edges[match.id] = edge
            }
        }
        edgesByServiceID = edges
    }

    private func loadGeometry(for matches: [OnDemandServiceMatch]) {
        geometryTask?.cancel()
        let missing = matches.map(\.id).filter { fullAreasByServiceID[$0] == nil }
        guard !missing.isEmpty else { return }
        geometryTask = Task { [weak self] in
            for serviceID in missing {
                guard let self, !Task.isCancelled else { return }
                do {
                    let areas = try await fullAreas(for: serviceID)
                    guard !Task.isCancelled else { return }
                    fullAreasByServiceID[serviceID] = areas
                    failedGeometryServiceIDs.remove(serviceID)
                    updateEdges()
                } catch {
                    guard !Task.isCancelled, !error.isCancellation else { return }
                    failedGeometryServiceIDs.insert(serviceID)
                }
            }
        }
    }

    private static func distanceMeters(_ lhs: CLLocationCoordinate2D, _ rhs: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
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
            return try await currentDeploymentResult(of: task, deployment: deployment)
        }

        let radius = configuration.radiusMeters
        let task = Task {
            let services = try await apiService.getOnDemandServices(near: coordinate, radiusMeters: radius, geometryDetail: .none).list
            // A reset cancels this task, but the response may already be in hand.
            try Task.checkCancellation()
            return services
        }
        inFlight[inFlightKey] = task
        defer {
            // A deployment reset may have let a newer probe take this key meanwhile.
            if inFlight[inFlightKey] == task { inFlight[inFlightKey] = nil }
        }

        let services = try await currentDeploymentResult(of: task, deployment: deployment)
        let entry = CacheEntry(services: services, fetchedAt: now())
        if exact {
            exactCache[key] = entry
        } else {
            probeCache[key] = entry
        }
        return services
    }

    /// Awaits a probe for its owner and every joiner alike, so each discards a
    /// result whose deployment is no longer current (spec 2.7).
    /// `getOnDemandServices(near:)` records a 404 in `onDemandSupport` itself;
    /// any other failure is transient: rethrown, nothing cached.
    private func currentDeploymentResult(of task: Task<[OnDemandService], Error>, deployment: String) async throws -> [OnDemandService] {
        do {
            let services = try await task.value
            try discardUnlessCurrent(deployment)
            return services
        } catch let error as APIError {
            if case .requestNotFound = error, deployment == currentDeployment {
                isUnsupported = true
            }
            throw error
        }
    }

    private func discardUnlessCurrent(_ deployment: String) throws {
        guard deployment == currentDeployment else { throw CancellationError() }
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

// MARK: - LocationServiceDelegate

extension OnDemandProbeController: LocationServiceDelegate {
    func locationService(_ service: LocationService, locationChanged location: CLLocation) {
        locationDidUpdate(location)
    }

    func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        locationAuthorizationDidChange()
    }
}
