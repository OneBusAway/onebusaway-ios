//
//  RESTAPIService+Get.swift
//  OBAKitCore
//
//  Created by Alan Chu on 12/28/22.
//

import MapKit

extension RESTAPIService {
    public nonisolated func getStop(id: String) async throws -> RESTAPIResponse<Stop> {
        let url = self.urlBuilder.getStop(stopID: id)
        return try await self.data(for: url, decodeAs: RESTAPIResponse<Stop>.self)
    }

    public nonisolated func getStop(region: MKCoordinateRegion) async throws -> RESTAPIResponse<[Stop]> {
        let url = self.urlBuilder.getStops(region: region)
        return try await self.data(for: url, decodeAs: RESTAPIResponse<[Stop]>.self)
    }
}
