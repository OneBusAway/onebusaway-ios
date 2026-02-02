//
//  SearchViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import MapKit
import OBAKitCore

/// Manages search state and execution for SwiftUI search views
@MainActor
class SearchViewModel: ObservableObject {
    // MARK: - Published State

    @Published var searchState: SearchState = .idle
    @Published var routeResults: [Route] = []
    @Published var stopResults: [Stop] = []
    @Published var mapItemResults: [MKMapItem] = []
    @Published var vehicleResults: [AgencyVehicle] = []

    // MARK: - Search State Enum

    enum SearchState: Equatable {
        case idle
        case searching
        case results(SearchType)
        case error(String)

        static func == (lhs: SearchState, rhs: SearchState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.searching, .searching):
                return true
            case let (.results(lhsType), .results(rhsType)):
                return lhsType == rhsType
            case let (.error(lhsMsg), .error(rhsMsg)):
                return lhsMsg == rhsMsg
            default:
                return false
            }
        }
    }

    // MARK: - Dependencies

    private let application: Application

    // MARK: - Computed Properties

    var hasResults: Bool {
        switch searchState {
        case .results(let type):
            switch type {
            case .route: return !routeResults.isEmpty
            case .stopNumber: return !stopResults.isEmpty
            case .address: return !mapItemResults.isEmpty
            case .vehicleID: return !vehicleResults.isEmpty
            }
        default:
            return false
        }
    }

    var resultsCount: Int {
        switch searchState {
        case .results(let type):
            switch type {
            case .route: return routeResults.count
            case .stopNumber: return stopResults.count
            case .address: return mapItemResults.count
            case .vehicleID: return vehicleResults.count
            }
        default:
            return 0
        }
    }

    // MARK: - Initialization

    init(application: Application) {
        self.application = application
    }

    // MARK: - Search Execution

    func executeSearch(type: SearchType, query: String) async {
        guard !query.isEmpty else { return }

        clearResults()
        searchState = .searching

        switch type {
        case .address:
            await searchAddress(query: query)
        case .route:
            await searchRoute(query: query)
        case .stopNumber:
            await searchStopNumber(query: query)
        case .vehicleID:
            await searchVehicleID(query: query)
        }
    }

    func clearResults() {
        routeResults = []
        stopResults = []
        mapItemResults = []
        vehicleResults = []
        searchState = .idle
    }

    // MARK: - Private Search Methods

    private func searchAddress(query: String) async {
        guard
            let apiService = application.apiService,
            let mapRect = application.mapRegionManager.lastVisibleMapRect
        else {
            searchState = .error("Unable to search. Please try again.")
            return
        }

        do {
            let results = try await apiService.getPlacemarks(query: query, region: MKCoordinateRegion(mapRect))
            mapItemResults = results.mapItems
            searchState = .results(.address)
        } catch {
            searchState = .error(error.localizedDescription)
        }
    }

    private func searchRoute(query: String) async {
        guard
            let apiService = application.apiService,
            let mapRect = application.mapRegionManager.lastVisibleMapRect
        else {
            searchState = .error("Unable to search. Please try again.")
            return
        }

        do {
            let response = try await apiService.getRoute(query: query, region: CLCircularRegion(mapRect: mapRect))
            routeResults = response.list
            searchState = .results(.route)
        } catch {
            searchState = .error(error.localizedDescription)
        }
    }

    private func searchStopNumber(query: String) async {
        guard
            let apiService = application.apiService,
            let currentRegion = application.regionsService.currentRegion
        else {
            searchState = .error("Unable to search. Please try again.")
            return
        }

        let region = CLCircularRegion(mapRect: currentRegion.serviceRect)

        do {
            let stops = try await apiService.getStops(circularRegion: region, query: query).list
            stopResults = stops
            searchState = .results(.stopNumber)
        } catch {
            searchState = .error(error.localizedDescription)
        }
    }

    private func searchVehicleID(query: String) async {
        guard let obacoService = application.obacoService else {
            searchState = .error("Vehicle search is not available.")
            return
        }

        do {
            let vehicles = try await obacoService.getVehicles(matching: query)
            vehicleResults = vehicles
            searchState = .results(.vehicleID)
        } catch {
            searchState = .error(error.localizedDescription)
        }
    }
}
