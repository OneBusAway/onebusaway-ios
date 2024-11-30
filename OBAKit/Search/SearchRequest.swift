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

    public func search(request: SearchRequest) async {
        switch request.searchType {
        case .address:    await searchAddress(request: request)
        case .route:      await searchRoute(request: request)
        case .stopNumber: searchStopNumber(request: request)
        case .vehicleID:  await searchVehicleID(request: request)
        }
    }

    private func searchAddress(request: SearchRequest) async {
        guard
            let apiService = application.apiService,
            let mapRect = await application.mapRegionManager.lastVisibleMapRect
        else {
            return
        }

        let searchResponse: SearchResponse
        do {
            let results = try await apiService.getPlacemarks(query: request.query, region: MKCoordinateRegion(mapRect))
            searchResponse = SearchResponse(request: request, results: results.mapItems, boundingRegion: results.boundingRegion, error: nil)
        } catch {
            searchResponse = SearchResponse(request: request, results: [], boundingRegion: nil, error: error)
        }

        await MainActor.run {
            self.application.mapRegionManager.searchResponse = searchResponse
        }
    }

    private func searchRoute(request: SearchRequest) async {
        guard
            let apiService = application.apiService,
            let mapRect = await application.mapRegionManager.lastVisibleMapRect
        else {
            return
        }

        do {
            let response = try await apiService.getRoute(query: request.query, region: CLCircularRegion(mapRect: mapRect))
            self.application.mapRegionManager.searchResponse = SearchResponse(request: request, results: response.list, boundingRegion: nil, error: nil)
        } catch {
            await self.application.displayError(error)
        }
    }

    private func searchStopNumber(request: SearchRequest) {
        guard let apiService = application.apiService else {
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

    private func searchVehicleID(request: SearchRequest) async {
        guard let obacoService = application.obacoService else { return }

        await ProgressHUD.show()

        do {
            let vehicles = try await obacoService.getVehicles(matching: request.query)
            self.processSearchResults(request: request, matchingVehicles: vehicles)
        } catch {
            await self.application.displayError(error)
        }

        await ProgressHUD.dismiss()
    }

    private func processSearchResults(request: SearchRequest, matchingVehicles: [AgencyVehicle]) {
        guard let apiService = application.apiService else { return }

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
