//
//  RESTAPIService+OnDemand.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit

extension RESTAPIService {

    // MARK: - On-demand services (`/api/ondemand`, GTFS-Flex)

    /// Retrieves one on-demand service with its full rules and references.
    ///
    /// - API Endpoint: `/api/ondemand/service/{id}.json`
    ///
    /// - parameter id: The combined service ID (for flex, the route's combined ID).
    /// - parameter geometryDetail: Defaults to the server default, `full`.
    ///   Screens pass `.simplified`.
    /// - throws: ``APIError`` or other errors. A 404 here means an unknown
    ///   service ID, never that the server lacks the namespace.
    /// - returns: The ``RESTAPIResponse`` for ``OnDemandService``.
    public nonisolated func getOnDemandService(id: String, geometryDetail: OnDemandGeometryDetail = .full) async throws -> RESTAPIResponse<OnDemandService> {
        return try await getData(
            for: urlBuilder.getOnDemandService(id: id, geometryDetail: geometryDetail),
            decodeRESTAPIResponseAs: OnDemandService.self
        )
    }

    /// Retrieves every on-demand service of an agency.
    ///
    /// - API Endpoint: `/api/ondemand/services-for-agency/{id}.json`
    ///
    /// - throws: ``APIError`` or other errors. A 404 means an unknown agency
    ///   ID (wiki §3.3); a known agency with no services returns an empty list.
    /// - returns: The ``RESTAPIResponse`` for [``OnDemandService``].
    public nonisolated func getOnDemandServices(agencyID: String, geometryDetail: OnDemandGeometryDetail = .simplified) async throws -> RESTAPIResponse<[OnDemandService]> {
        return try await getData(
            for: urlBuilder.getOnDemandServices(agencyID: agencyID, geometryDetail: geometryDetail),
            decodeRESTAPIResponseAs: [OnDemandService].self
        )
    }

    /// Retrieves the on-demand services whose zones or stops intersect `region`
    /// (the server's viewport mode).
    ///
    /// This is the **only** call that probes for the namespace: a
    /// `.requestNotFound` here — a real HTTP 404, or the blank 200 that
    /// `APIService+GetData` maps to the same case — records the server in
    /// ``onDemandSupport`` for the rest of the process. Every other failure,
    /// including `.invalidContentType` and decode errors, is transient and is
    /// simply rethrown.
    ///
    /// - API Endpoint: `/api/ondemand/services-for-location.json`
    ///
    /// - throws: ``APIError`` or other errors.
    /// - returns: The ``RESTAPIResponse`` for [``OnDemandService``]; each
    ///   element carries a ``MatchReason``.
    public nonisolated func getOnDemandServices(region: MKCoordinateRegion, geometryDetail: OnDemandGeometryDetail = .simplified) async throws -> RESTAPIResponse<[OnDemandService]> {
        do {
            return try await getData(
                for: urlBuilder.getOnDemandServices(region: region, geometryDetail: geometryDetail),
                decodeRESTAPIResponseAs: [OnDemandService].self
            )
        } catch let error as APIError {
            if case .requestNotFound = error {
                onDemandSupport.recordAbsent(baseURL: baseURL)
            }
            throw error
        }
    }
}
