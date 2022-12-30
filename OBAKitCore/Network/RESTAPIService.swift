//
//  RESTAPIService.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import MapKit

/// Loads data from a OneBusAway REST API server and returns it as model objects.

@available(*, deprecated, message: "Use RESTAPIService")
public class _RESTAPIService: APIService {
    lazy var URLBuilder = RESTAPIURLBuilder(baseURL: baseURL, defaultQueryItems: defaultQueryItems)

    private let regionIdentifier: Int

    /// Creates a new instance of `RESTAPIService`.
    /// - Parameters:
    ///   - baseURL: The base URL for the service you will be using.
    ///   - apiKey: The API key for the service you will be using. Passed along as `key` in query params.
    ///   - uuid: A unique, anonymous user ID.
    ///   - appVersion: The version of the app making the request.
    ///   - networkQueue: The queue on which all network operations will be performed.
    ///   - dataLoader: The object used to perform network operations. A protocol facade is provided here to simplify testing.
    ///   - regionIdentifier: The unique ID of the `Region` that this service object is tied to.
    public init(baseURL: URL, apiKey: String, uuid: String, appVersion: String, networkQueue: OperationQueue, dataLoader: URLDataLoader, regionIdentifier: Int) {
        self.regionIdentifier = regionIdentifier
        super.init(baseURL: baseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, networkQueue: networkQueue, dataLoader: dataLoader)
    }

    private func buildOperation<T>(type: T.Type, URL: URL) -> DecodableOperation<T> where T: Decodable {
        return DecodableOperation(type: type, decoder: JSONDecoder.RESTDecoder(regionIdentifier: regionIdentifier), URL: URL, dataLoader: dataLoader)
    }

    // MARK: - Stops
    @available(*, deprecated, message: "Use async.")
    func getStop(id: String, enqueue: Bool = true) -> DecodableOperation<RESTAPIResponse<Stop>> {
        let url = URLBuilder.getStop(stopID: id)
        let operation = buildOperation(type: RESTAPIResponse<Stop>.self, URL: url)
        if enqueue { enqueueOperation(operation) }
        return operation
    }

    // MARK: - Arrivals and Departures for Stop
    @available(*, deprecated, message: "Use async.")
    public func getArrivalsAndDeparturesForStop(id: StopID, minutesBefore: UInt, minutesAfter: UInt, enqueue: Bool = true) -> DecodableOperation<RESTAPIResponse<StopArrivals>> {
        let url = URLBuilder.getArrivalsAndDeparturesForStop(id: id, minutesBefore: minutesBefore, minutesAfter: minutesAfter)
        let operation = buildOperation(type: RESTAPIResponse<StopArrivals>.self, URL: url)
        if enqueue { enqueueOperation(operation) }
        return operation
    }

    // MARK: - Arrival and Departure for Stop
    @available(*, deprecated, message: "Use async.")
    public func getTripArrivalDepartureAtStop(stopID: StopID, tripID: String, serviceDate: Date, vehicleID: String?, stopSequence: Int) -> DecodableOperation<RESTAPIResponse<ArrivalDeparture>> {
        let url = URLBuilder.getTripArrivalDepartureAtStop(stopID: stopID, tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopSequence: stopSequence)
        let operation = buildOperation(type: RESTAPIResponse<ArrivalDeparture>.self, URL: url)
        enqueueOperation(operation)
        return operation
    }

    // MARK: - Trip Details
    @available(*, deprecated, message: "Use async.")
    public func getTrip(tripID: String, vehicleID: String?, serviceDate: Date?) -> DecodableOperation<RESTAPIResponse<TripDetails>> {
        let url = URLBuilder.getTrip(tripID: tripID, vehicleID: vehicleID, serviceDate: serviceDate)
        let operation = buildOperation(type: RESTAPIResponse<TripDetails>.self, URL: url)
        enqueueOperation(operation)
        return operation
    }

    // MARK: - Search

    /// Performs a local search and returns matching results
    ///
    /// - Parameters:
    ///   - query: The term for which to search.
    ///   - region: The coordinate region in which to search.
    /// - Returns: The enqueued network operation.
    public func getPlacemarks(query: String, region: MKCoordinateRegion) -> PlacemarkSearchOperation {
        let operation = PlacemarkSearchOperation(query: query, region: region)
        enqueueOperation(operation)
        return operation
    }

    // MARK: - Shapes

    /// Retrieve a shape (the path traveled by a transit vehicle) by id
    ///
    /// - API Endpoint: `/api/where/shape/{id}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/shape.html)
    ///
    /// - Parameters:
    ///   - id: The ID of the shape to retrieve.
    /// - Returns: The enqueued network operation.
    public func getShape(id: String) -> DecodableOperation<RESTAPIResponse<PolylineEntity>> {
        let url = URLBuilder.getShape(id: id)
        let operation = buildOperation(type: RESTAPIResponse<PolylineEntity>.self, URL: url)
        enqueueOperation(operation)
        return operation
    }

    // MARK: - Agencies

    @available(*, deprecated, message: "Use async.")
    public func getAgenciesWithCoverage() -> DecodableOperation<RESTAPIResponse<[AgencyWithCoverage]>> {
        let url = URLBuilder.getAgenciesWithCoverage()
        let operation = buildOperation(type: RESTAPIResponse<[AgencyWithCoverage]>.self, URL: url)
        enqueueOperation(operation)
        return operation
    }
}
