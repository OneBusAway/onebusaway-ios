//
//  SearchRequest.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/17/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import Foundation
import MapKit
import OBAKitCore

/// Describes what kind of search the user is performing.
public enum SearchType: Int {
    case address, route, stopNumber, vehicleID
}

/// Create a `SearchRequest` to define what the user is searching for.
public class SearchRequest: NSObject {
    public let query: String
    public let searchType: SearchType

    public init(query: String, type: SearchType) {
        self.query = query
        self.searchType = type
    }
}

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

    // MARK: - Private Helpers

    private func searchAddress(request: SearchRequest) {
        guard
            let apiService = application.restAPIService,
            let mapRect = application.mapRegionManager.lastVisibleMapRect
        else {
            return
        }

        let op = apiService.getPlacemarks(query: request.query, region: MKCoordinateRegion(mapRect))
        op.completionBlock = { [weak self] in
            guard let self = self else { return }

            self.application.mapRegionManager.searchResponse = SearchResponse(request: request, results: op.response?.mapItems ?? [MKMapItem](), boundingRegion: op.response?.boundingRegion, error: op.error)
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
                print("TODO FIXME handle error! \(error)")
            case .success(let response):
                self.application.mapRegionManager.searchResponse = SearchResponse(request: request, results: response.list, boundingRegion: nil, error: op.error)
            }
        }
    }

    private func searchStopNumber(request: SearchRequest) {
        guard let apiService = application.restAPIService else {
            return
        }

        let region = CLCircularRegion(mapRect: application.regionsService.currentRegion!.serviceRect)
        let op = apiService.getStops(circularRegion: region, query: request.query)
        op.complete { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                print("TODO FIXME handle error! \(error)")
            case .success(let response):
                self.application.mapRegionManager.searchResponse = SearchResponse(request: request, results: response.list, boundingRegion: nil, error: op.error)
            }
        }
    }

    private func searchVehicleID(request: SearchRequest) {
        guard let obacoService = application.obacoService else { return }

        SVProgressHUD.show()

        let op = obacoService.getVehicles(matching: request.query)
        op.complete { [weak self] result in
            SVProgressHUD.dismiss()
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                print("TODO FIXME handle error! \(error)")
            case .success(let response):
                self.processSearchResults(request: request, matchingVehicles: response)
            }
        }
    }

    private func processSearchResults(request: SearchRequest, matchingVehicles: [AgencyVehicle]) {
        guard let apiService = application.restAPIService else { return }

        if matchingVehicles.count > 1 {
            // Show a disambiguation UI.
            application.mapRegionManager.searchResponse = SearchResponse(request: request, results: matchingVehicles, boundingRegion: nil, error: nil)
            return
        }

        if matchingVehicles.count == 1, let vehicleID = matchingVehicles.first?.vehicleID {
            // One result. Find that vehicle and show it.
            let op = apiService.getVehicle(vehicleID)
            op.complete { [weak self] result in
                guard let self = self else { return }

                switch result {
                case .failure(let error):
                    print("TODO FIXME handle error! \(error)")
                case .success(let response):
                    self.application.mapRegionManager.searchResponse = SearchResponse(request: request, results: [response.list], boundingRegion: nil, error: nil)
                }
            }
            return
        }

        // No results :(
        self.application.mapRegionManager.searchResponse = SearchResponse(request: request, results: [], boundingRegion: nil, error: nil)
    }
}
