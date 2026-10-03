//
//  OnDemandGeometryCache.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Full (`geometryDetail=full`) areas per `(deployment, serviceId)`, kept for
/// the process lifetime and fetched lazily for matched services (spec 2.7).
/// Two callers asking for the same service share one fetch.
actor OnDemandGeometryCache {

    /// Injected so tests can count fetches. Production passes a closure over
    /// `RESTAPIService.getOnDemandService(id:geometryDetail: .full)`. The
    /// service is an argument so the closure captures nothing that is not
    /// `Sendable` (`Application` is not).
    typealias Fetch = @Sendable (_ apiService: RESTAPIService, _ serviceID: String) async throws -> [ServiceArea]

    private struct Key: Hashable {
        let deployment: String
        let serviceID: String
    }

    private let fetch: Fetch
    private var cached: [Key: [ServiceArea]] = [:]
    private var inFlight: [Key: Task<[ServiceArea], Error>] = [:]

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    func areas(deployment: String, serviceID: String, apiService: RESTAPIService) async throws -> [ServiceArea] {
        let key = Key(deployment: deployment, serviceID: serviceID)
        if let areas = cached[key] {
            return areas
        }
        if let task = inFlight[key] {
            return try await task.value
        }

        let fetch = self.fetch
        let task = Task { try await fetch(apiService, serviceID) }
        inFlight[key] = task
        defer {
            // `cancelAll()` may have let a newer fetch take this key meanwhile.
            if inFlight[key] == task { inFlight[key] = nil }
        }
        let areas = try await task.value
        cached[key] = areas
        return areas
    }

    func cachedAreas(deployment: String, serviceID: String) -> [ServiceArea]? {
        cached[Key(deployment: deployment, serviceID: serviceID)]
    }

    /// Cancels every fetch in flight; cached areas stay, they are keyed by deployment.
    func cancelAll() {
        for task in inFlight.values {
            task.cancel()
        }
        inFlight = [:]
    }
}
