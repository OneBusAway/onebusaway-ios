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

    public func search(request: SearchRequest) {
        switch request.searchType {
        case .address:    searchAddress(request: request)
        case .route:      searchRoute(request: request)
        case .stopNumber: searchStopNumber(request: request)
        case .vehicleID:  searchVehicleID(request: request)
        }
    }

    private func searchAddress(request: SearchRequest) {
        guard
            let apiService = application.restAPIService,
            let mapRect = application.mapRegionManager.lastVisibleMapRect
        else {
            return
        }

        let op = apiService.getPlacemarks(query: request.query, region: MKCoordinateRegion(mapRect))
        op.completionBlock = { [weak self] in
            DispatchQueue.main.async {
                self?.application.mapRegionManager.searchResponse = SearchResponse(request: request, results: op.response?.mapItems ?? [MKMapItem](), boundingRegion: op.response?.boundingRegion, error: op.error)
            }
        }
    }

    private func searchRoute(request: SearchRequest) {
        guard
            let apiService = application.restAPIService,
            let mapRect = application.mapRegionManager.lastVisibleMapRect
        else {
            return
        }

        let op = apiService.getRoute(query: request.query, region: CLCircularRegion(mapRect: mapRect))
        op.complete { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                Task { @MainActor in
                    self.application.displayError(error)
                }
            case .success(let response):
                self.application.mapRegionManager.searchResponse = SearchResponse(request: request, results: response.list, boundingRegion: nil, error: op.error)
            }
        }
    }

    private func searchStopNumber(request: SearchRequest) {
        guard let apiService = application.betterAPIService else {
            return
        }

        let region = CLCircularRegion(mapRect: application.regionsService.currentRegion!.serviceRect)

        Task(priority: .userInitiated) {
            do {
                let stops = try await apiService.getStops(circularRegion: region, query: request.query).list
                await MainActor.run {
                    self.application.mapRegionManager.searchResponse = SearchResponse(request: request, results: stops, boundingRegion: nil, error: nil)
                }
            } catch {
                await self.application.displayError(error)
                await MainActor.run {
                    self.application.mapRegionManager.searchResponse = SearchResponse(request: request, results: [], boundingRegion: nil, error: error)
                }
            }
        }
    }

    private func searchVehicleID(request: SearchRequest) {
        guard let obacoService = application.obacoService else { return }

        ProgressHUD.show()

        let op = obacoService.getVehicles(matching: request.query)
        op.complete { [weak self] result in
            ProgressHUD.dismiss()
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                Task { @MainActor in
                    self.application.displayError(error)
                }
            case .success(let response):
                self.processSearchResults(request: request, matchingVehicles: response)
            }
        }
    }

    private func processSearchResults(request: SearchRequest, matchingVehicles: [AgencyVehicle]) {
        guard let apiService = application.betterAPIService else { return }

        if matchingVehicles.count > 1 {
            // Show a disambiguation UI.
            application.mapRegionManager.searchResponse = SearchResponse(request: request, results: matchingVehicles, boundingRegion: nil, error: nil)
            return
        }

        if matchingVehicles.count == 1, let vehicleID = matchingVehicles.first?.vehicleID {
            // One result. Find that vehicle and show it.
            Task(priority: .userInitiated) {
                do {
                    let vehicle = try await apiService.getVehicle(vehicleID: vehicleID).entry
                    await MainActor.run {
                        self.application.mapRegionManager.searchResponse = SearchResponse(request: request, results: [vehicle], boundingRegion: nil, error: nil)
                    }
                } catch {
                    await self.application.displayError(error)
                    await MainActor.run {
                        self.application.mapRegionManager.searchResponse = SearchResponse(request: request, results: [], boundingRegion: nil, error: error)
                    }
                }

            }
        } else {
            // No results :(
            self.application.mapRegionManager.searchResponse = SearchResponse(request: request, results: [], boundingRegion: nil, error: nil)
        }
    }
}
