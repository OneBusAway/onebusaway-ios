//
//  SearchRequest.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import OBAKitCore

// MARK: - SearchError

/// Defines errors that can occur during search operations in the app.
public enum SearchError: Error, LocalizedError, Equatable {
    case noTripsAvailable

    public var errorDescription: String? {
        switch self {
        case .noTripsAvailable:
            return OBALoc("search_results_controller.no_trips_available", value: "This vehicle is not currently on any trips.", comment: "Error message shown when a vehicle has no trips available.")
        }
    }
}

// MARK: - SearchType

/// Describes what kind of search the user is performing.
public enum SearchType: Int {
    case address, route, stopNumber, vehicleID
}

// MARK: - SearchRequest

/// Create a `SearchRequest` to define what the user is searching for.
public class SearchRequest: NSObject {
    public let query: String
    public let searchType: SearchType

    public init(query: String, type: SearchType) {
        self.query = query
        self.searchType = type
    }
}

// MARK: - SearchResponse

/// This class manages the results of a user search.
public class SearchResponse: NSObject {
    public let request: SearchRequest
    public let results: [Any]
    public let boundingRegion: MKCoordinateRegion?
    public let error: Error?

    public init(request: SearchRequest, results: [Any], boundingRegion: MKCoordinateRegion?, error: Error?) {
        self.request = request
        self.results = results
        self.boundingRegion = boundingRegion
        self.error = error
    }

    public init(response: SearchResponse, substituteResult: Any) {
        self.request = response.request
        self.results = [substituteResult]
        self.boundingRegion = response.boundingRegion
        self.error = response.error
    }

    /// Returns true if the results count does not equal 1.
    /// In other words, show the result directly if there is only a single match.
    public var needsDisambiguation: Bool {
        return results.count != 1
    }
}

// MARK: - SearchManager

public class SearchManager: NSObject {
    private let application: Application

    public init(application: Application) {
        self.application = application
    }

    // MARK: - Publishing entry point (UIKit)

    /// Performs `request` and publishes the result through `MapRegionManager`, which
    /// fans out to `MapRegionDelegate`. Error handling deliberately differs per
    /// search type — that asymmetry is pre-existing behavior the UIKit map depends
    /// on, not an oversight:
    ///   - `.address` publishes an error response and shows no alert.
    ///   - `.stopNumber` shows an alert *and* publishes an error response.
    ///   - `.route` / `.vehicleID` show an alert only; publishing an empty response
    ///     would additionally trigger the "No search results were found" alert via
    ///     `notifyDelegatesNoSearchResults`, double-alerting the user.
    public func search(request: SearchRequest) async {
        if request.searchType == .vehicleID {
            ProgressHUD.show()
        }
        defer {
            if request.searchType == .vehicleID {
                ProgressHUD.dismiss()
            }
        }

        do {
            guard let response = try await fetchResults(for: request) else { return }
            application.mapRegionManager.searchResponse = response
        } catch {
            switch request.searchType {
            case .address:
                application.mapRegionManager.searchResponse = SearchResponse(request: request, results: [], boundingRegion: nil, error: error)
            case .stopNumber:
                await application.displayError(error)
                application.mapRegionManager.searchResponse = SearchResponse(request: request, results: [], boundingRegion: nil, error: error)
            case .route, .vehicleID:
                await application.displayError(error)
            }
        }
    }

    // MARK: - Returning entry point (SwiftUI)

    /// Performs `request` and returns the response instead of publishing it.
    ///
    /// Returns `nil` when the search could not run at all — no API service, no
    /// Obaco service, or no map rect — mirroring the `guard … else { return }`
    /// bail-outs the publishing path has always had.
    func fetchResults(for request: SearchRequest) async throws -> SearchResponse? {
        switch request.searchType {
        case .address:    return try await fetchAddress(request: request)
        case .route:      return try await fetchRoute(request: request)
        case .stopNumber: return try await fetchStopNumber(request: request)
        case .vehicleID:  return try await fetchVehicleID(request: request)
        }
    }

    private func fetchAddress(request: SearchRequest) async throws -> SearchResponse? {
        guard
            let apiService = application.apiService,
            let mapRect = application.mapRegionManager.lastVisibleMapRect
        else { return nil }

        let results = try await apiService.getPlacemarks(query: request.query, region: MKCoordinateRegion(mapRect))
        return SearchResponse(request: request, results: results.mapItems, boundingRegion: results.boundingRegion, error: nil)
    }

    private func fetchRoute(request: SearchRequest) async throws -> SearchResponse? {
        guard
            let apiService = application.apiService,
            let mapRect = application.mapRegionManager.lastVisibleMapRect
        else { return nil }

        let response = try await apiService.getRoute(query: request.query, region: CLCircularRegion(mapRect: mapRect))
        return SearchResponse(request: request, results: response.list, boundingRegion: nil, error: nil)
    }

    private func fetchStopNumber(request: SearchRequest) async throws -> SearchResponse? {
        guard
            let apiService = application.apiService,
            let serviceRect = application.regionsService.currentRegion?.serviceRect
        else { return nil }

        let stops = try await apiService.getStops(circularRegion: CLCircularRegion(mapRect: serviceRect), query: request.query).list
        return SearchResponse(request: request, results: stops, boundingRegion: nil, error: nil)
    }

    private func fetchVehicleID(request: SearchRequest) async throws -> SearchResponse? {
        guard let obacoService = application.obacoService else { return nil }

        let matchingVehicles = try await obacoService.getVehicles(matching: request.query)

        guard let apiService = application.apiService else { return nil }

        if matchingVehicles.count > 1 {
            return SearchResponse(request: request, results: matchingVehicles, boundingRegion: nil, error: nil)
        }

        guard matchingVehicles.count == 1, let vehicleID = matchingVehicles.first?.vehicleID else {
            return SearchResponse(request: request, results: [], boundingRegion: nil, error: nil)
        }

        do {
            let vehicle = try await apiService.getVehicle(vehicleID: vehicleID).entry
            return SearchResponse(request: request, results: [vehicle], boundingRegion: nil, error: nil)
        } catch {
            // Preserved from `processSearchResults`: this inner failure alerted and
            // published an empty error response rather than propagating. Kept as-is
            // so the UIKit path is unchanged; revisit when the SwiftUI panel is the
            // only surface.
            await application.displayError(error)
            return SearchResponse(request: request, results: [], boundingRegion: nil, error: error)
        }
    }
}
