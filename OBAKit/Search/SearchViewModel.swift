//
//  SearchViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

@MainActor
final class SearchViewModel: ObservableObject {

    @Published private(set) var vehicleSearchResponse: SearchResponse?
    @Published private(set) var vehicleError: Error?

    let subtitle: String
    let results: [Any]

    private let searchResponse: SearchResponse
    private let apiService: RESTAPIService?
    private var isLoading = false

    convenience init(searchResponse: SearchResponse, application: Application) {
        self.init(searchResponse: searchResponse, apiService: application.apiService)
    }

    init(searchResponse: SearchResponse, apiService: RESTAPIService?) {
        self.searchResponse = searchResponse
        self.apiService = apiService
        self.subtitle = SearchViewModel.subtitleText(from: searchResponse)
        self.results = searchResponse.results
    }

    func response(substituting item: Any) -> SearchResponse {
        SearchResponse(response: searchResponse, substituteResult: item)
    }

    func selectVehicle(vehicleID: String) async {
        guard !isLoading else { return }
        guard let apiService else {
            // Misconfiguration (no API service available). Surface it through the same
            // error channel as a request failure so the screen doesn't silently no-op.
            vehicleError = UnstructuredError(OBALoc(
                "search_results_controller.no_api_service_error",
                value: "No transit data service is available. Please choose a region in Settings.",
                comment: "Error shown when vehicle search is attempted with no API service configured (e.g. no region selected)."
            ))
            return
        }
        isLoading = true
        vehicleError = nil
        vehicleSearchResponse = nil
        defer { isLoading = false }
        do {
            let vehicle = try await apiService.getVehicle(vehicleID: vehicleID).entry
            vehicleSearchResponse = SearchResponse(response: searchResponse, substituteResult: vehicle)
        } catch let DecodingError.keyNotFound(key, _) where key.stringValue == "tripId" {
            // VehicleStatus requires `tripId`; its absence means the vehicle isn't on
            // any trip right now. Any *other* missing key signals a real decode failure
            // (renamed field, malformed payload) and should surface as-is.
            vehicleError = SearchError.noTripsAvailable
        } catch {
            Logger.error("selectVehicle decode failure: \(error)")
            vehicleError = error
        }
    }

    private static func subtitleText(from response: SearchResponse) -> String {
        let subtitleFormat: String
        switch response.request.searchType {
        case .address:
            subtitleFormat = OBALoc("search_results_controller.subtitle.address_fmt", value: "%@", comment: "A format string for address searches. In English, this is just the address itself without any adornment.")
        case .route:
            subtitleFormat = OBALoc("search_results_controller.subtitle.route_fmt", value: "Route %@", comment: "A format string for route searches. e.g. in english: Route \"{SEARCH TEXT}\"")
        case .stopNumber:
            subtitleFormat = OBALoc("search_results_controller.subtitle.stop_number_fmt", value: "Stop number %@", comment: "A format string for stop number searches. e.g. in english: Stop number \"{SEARCH TEXT}\"")
        case .vehicleID:
            subtitleFormat = OBALoc("search_results_controller.subtitle.vehicle_id_fmt", value: "Vehicle ID %@", comment: "A format string for vehicle ID searches. e.g. in english: Vehicle ID \"{SEARCH TEXT}\"")
        }
        return String(format: subtitleFormat, response.request.query)
    }
}
