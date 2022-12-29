//
//  RESTAPIService+Get.swift
//  OBAKitCore
//
//  Created by Alan Chu on 12/28/22.
//

import MapKit

extension RESTAPIService {
    // MARK: - Stops
    /// Retrieves stops near the provided `coordinate`.
    ///
    /// - API Endpoint: `/api/where/stops-for-location.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/stops-for-location.html)
    ///
    /// - parameter coordinate: The coordinate around which to search for stops.
    /// - throws: ``APIError`` or other errors.
    /// - returns: The ``RESTAPIResponse`` for [``Stop``].
    public nonisolated func getStops(coordinate: CLLocationCoordinate2D) async throws -> RESTAPIResponse<[Stop]> {
        return try await getData(
            for: urlBuilder.getStops(coordinate: coordinate),
            decodeRESTAPIResponseAs: [Stop].self
        )
    }

    public nonisolated func getStop(id: String) async throws -> RESTAPIResponse<Stop> {
        return try await getData(
            for: urlBuilder.getStop(stopID: id),
            decodeRESTAPIResponseAs: Stop.self
        )
    }

    public nonisolated func getStop(region: MKCoordinateRegion) async throws -> RESTAPIResponse<[Stop]> {
        return try await getData(
            for: urlBuilder.getStops(region: region),
            decodeRESTAPIResponseAs: [Stop].self
        )
    }
}
