//
//  SearchRequest.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/17/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import Foundation
import MapKit

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
        guard
            let modelService = application.restAPIModelService,
            let mapRect = application.mapRegionManager.lastVisibleMapRect
        else {
            return
        }

        switch request.searchType {
        case .address:
            let op = modelService.getPlacemarks(query: request.query, region: MKCoordinateRegion(mapRect))
            op.then { [weak self] in
                guard let self = self else { return }

                self.application.mapRegionManager.searchResponse = SearchResponse(request: request, results: op.response?.mapItems ?? [MKMapItem](), boundingRegion: op.response?.boundingRegion, error: op.error)
            }
        case .route:
            let op = modelService.getRoute(query: request.query, region: CLCircularRegion(mapRect: mapRect))
            op.then { [weak self] in
                guard let self = self else { return }
                self.application.mapRegionManager.searchResponse = SearchResponse(request: request, results: op.routes, boundingRegion: nil, error: op.error)
            }
        case .stopNumber:
            let region = CLCircularRegion(mapRect: application.regionsService.currentRegion!.serviceRect)
            let op = modelService.getStops(circularRegion: region, query: request.query)
            op.then { [weak self] in
                guard let self = self else { return }
                self.application.mapRegionManager.searchResponse = SearchResponse(request: request, results: op.stops, boundingRegion: nil, error: op.error)
            }
        case .vehicleID:
            let op = modelService.getVehicleStatus(request.query)
            op.then { [weak self] in
                guard let self = self else { return }
                self.application.mapRegionManager.searchResponse = SearchResponse(request: request, results: op.vehicles, boundingRegion: nil, error: op.error)
            }
        }
    }
}
