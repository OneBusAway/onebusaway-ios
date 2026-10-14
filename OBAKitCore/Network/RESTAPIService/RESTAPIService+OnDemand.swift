//
//  RESTAPIService+OnDemand.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
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
    /// `APIService+GetData` maps to the same case — or an HTML page (see
    /// ``APIError/meansOnDemandUnsupported``) records the server in
    /// ``onDemandSupport`` for the rest of the process. Every other failure,
    /// including other content types and decode errors, is transient and is
    /// simply rethrown.
    ///
    /// - API Endpoint: `/api/ondemand/services-for-location.json`
    ///
    /// - throws: ``APIError`` or other errors.
    /// - returns: The ``RESTAPIResponse`` for [``OnDemandService``]; each
    ///   element carries a ``MatchReason``.
    public nonisolated func getOnDemandServices(region: MKCoordinateRegion, geometryDetail: OnDemandGeometryDetail = .simplified) async throws -> RESTAPIResponse<[OnDemandService]> {
        try await getOnDemandServicesRecordingAbsence(url: urlBuilder.getOnDemandServices(region: region, geometryDetail: geometryDetail))
    }

    /// Retrieves the on-demand services around one point (the server's point
    /// mode): every service whose zone contains the point, whose boundary is
    /// within `radiusMeters`, or one of whose stops is. Each list element
    /// carries a ``MatchReason`` and each area a `distanceToArea`.
    ///
    /// Probes the namespace exactly as the viewport call does: a
    /// `.requestNotFound` or an HTML page records the server in ``onDemandSupport``.
    ///
    /// - API Endpoint: `/api/ondemand/services-for-location.json`
    public nonisolated func getOnDemandServices(near coordinate: CLLocationCoordinate2D, radiusMeters: Double, geometryDetail: OnDemandGeometryDetail = .none) async throws -> RESTAPIResponse<[OnDemandService]> {
        try await getOnDemandServicesRecordingAbsence(url: urlBuilder.getOnDemandServices(near: coordinate, radiusMeters: radiusMeters, geometryDetail: geometryDetail))
    }

    private nonisolated func getOnDemandServicesRecordingAbsence(url: URL) async throws -> RESTAPIResponse<[OnDemandService]> {
        do {
            return try await getData(for: url, decodeRESTAPIResponseAs: [OnDemandService].self)
        } catch let error as APIError {
            if error.meansOnDemandUnsupported {
                onDemandSupport.recordAbsent(baseURL: baseURL)
            }
            throw error
        }
    }
}
