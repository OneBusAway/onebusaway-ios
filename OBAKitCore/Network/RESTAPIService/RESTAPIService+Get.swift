//
//  RESTAPIService+Get.swift
//  OBAKitCore
//
//  Created by Alan Chu on 12/28/22.
//

import MapKit

extension RESTAPIService {
    // MARK: - Vehicle with ID

    /// Provides information on the vehicle with the specified ID.
    ///
    /// API Endpoint: `/api/where/vehicle/{id}.json`
    ///
    /// - important: Vehicle IDs are seldom identical to the IDs that are physically printed
    /// on buses. For example, in Puget Sound, a KC Metro bus that has the number `1234`
    /// printed on its side will likely have the vehicle ID `1_1234` to ensure that the vehicle ID
    /// is unique across the Puget Sound region with all of its agencies.
    ///
    /// - parameter vehicleID: Vehicle ID string
    /// - throws: ``APIError`` or other errors.
    /// - returns: The ``RESTAPIResponse`` for [``VehicleStatus``].
    public nonisolated func getVehicle(vehicleID: String) async throws -> RESTAPIResponse<VehicleStatus> {
        return try await getData(
            for: urlBuilder.getVehicleURL(vehicleID),
            decodeRESTAPIResponseAs: VehicleStatus.self
        )
    }

    /// Get extended trip details for a specific transit vehicle. That is, given a vehicle id for a transit vehicle
    /// currently operating in the field, return extended trip details about the current trip for the vehicle.
    ///
    /// - API Endpoint: `/api/where/trip-for-vehicle/{id}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/trip-for-vehicle.html)
    ///
    /// - important: Vehicle IDs are seldom identical to the IDs that are physically printed
    /// on buses. For example, in Puget Sound, a KC Metro bus that has the number `1234`
    /// printed on its side will likely have the vehicle ID `1_1234` to ensure that the vehicle ID
    /// is unique across the Puget Sound region with all of its agencies.
    ///
    /// - parameter vehicleID: The ID of the vehicle
    /// - throws: ``APIError`` or other errors.
    /// - returns: The ``RESTAPIResponse`` for [``TripDetails``].
    public nonisolated func getVehicleTrip(vehicleID: String) async throws -> RESTAPIResponse<TripDetails> {
        return try await getData(
            for: urlBuilder.getVehicleTrip(vehicleID: vehicleID),
            decodeRESTAPIResponseAs: TripDetails.self
        )
    }

    // MARK: - Current Time
    /// Retrieves the current system time of the OneBusAway server.
    ///
    /// - API Endpoint: `/api/where/current-time.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/current-time.html)
    ///
    /// - throws: ``APIError`` or other errors.
    /// - returns: ``CoreRESTAPIResponse``.
    public nonisolated func getCurrentTime() async throws -> CoreRESTAPIResponse {
        return try await getData(
            for: urlBuilder.getCurrentTime(),
            decodeAs: CoreRESTAPIResponse.self
        )
    }

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

    /// Retrieves stops within `region`.
    ///
    /// - API Endpoint: `/api/where/stops-for-location.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/stops-for-location.html)
    ///
    /// - important: Depending on the number of stops located within `region`, you may only receive back
    /// a subset of the total list of stops within `region`. Zoom in (i.e. provide a smaller region) to
    /// better guarantee that you will receive a full list.
    ///
    /// - parameter region: A coordinate region from which to search for stops.
    /// - throws: ``APIError`` or other errors.
    /// - returns: The ``RESTAPIResponse`` for [``Stop``].
    public nonisolated func getStops(region: MKCoordinateRegion) async throws -> RESTAPIResponse<[Stop]> {
        return try await getData(
            for: urlBuilder.getStops(region: region),
            decodeRESTAPIResponseAs: [Stop].self
        )
    }

    /// Retrieves stops within `circularRegion`.
    ///
    /// - API Endpoint: `/api/where/stops-for-location.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/stops-for-location.html)
    ///
    /// - important: Depending on the number of stops located within `circularRegion`, you may only receive back
    /// a subset of the total list of stops within `circularRegion`. Zoom in (i.e. provide a smaller region) to
    /// better guarantee that you will receive a full list.
    ///
    /// - parameter circularRegion: A circular region from which to search for stops.
    /// - parameter query: A search query for a specific stop code.
    /// - throws: ``APIError`` or other errors.
    /// - returns: The ``RESTAPIResponse`` for [``Stop``].
    public nonisolated func getStops(circularRegion: CLCircularRegion, query: String) async throws -> RESTAPIResponse<[Stop]> {
        return try await getData(
            for: urlBuilder.getStops(circularRegion: circularRegion, query: query),
            decodeRESTAPIResponseAs: [Stop].self
        )
    }

    /// Retrieves the stop with the specified ID.
    ///
    /// - API Endpoint: `/api/where/stop/{id}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/stop.html)
    ///
    /// - parameter id: The full, agency-prefixed ID of the stop.
    /// - throws: ``APIError`` or other errors.
    /// - returns: The ``RESTAPIResponse`` for ``Stop``.
    public nonisolated func getStop(id: String) async throws -> RESTAPIResponse<Stop> {
        return try await getData(
            for: urlBuilder.getStop(stopID: id),
            decodeRESTAPIResponseAs: Stop.self
        )
    }

    // MARK: - Arrival and Departures for Stop
    /// Retrieves a list of vehicle arrivals and departures for the specified stop for the time frame of
    /// `minutesBefore` to `minutesAfter`.
    ///
    /// - API Endpoint: `/api/where/arrivals-and-departures-for-stop/{id}.json`
    /// - [View REST API Documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/arrivals-and-departures-for-stop.html)
    ///
    /// - parameter id: The stop ID
    /// - parameter minutesBefore: How many minutes before now should Arrivals and Departures be returned for
    /// - parameter minutesAfter: How many minutes after now should Arrivals and Departures be returned for
    /// - throws: ``APIError`` or other errors.
    /// - returns: The ``RESTAPIResponse`` for ``StopArrivals``.
    public nonisolated func getArrivalsAndDeparturesForStop(id: StopID, minutesBefore: UInt, minutesAfter: UInt) async throws -> RESTAPIResponse<StopArrivals> {
        let url = urlBuilder.getArrivalsAndDeparturesForStop(id: id, minutesBefore: minutesBefore, minutesAfter: minutesAfter)
        return try await getData(
            for: url,
            decodeRESTAPIResponseAs: StopArrivals.self
        )
    }

    /// Get info about a single arrival and departure for a stop
    ///
    /// - API Endpoint: `/api/where/arrival-and-departure-for-stop/{id}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/arrival-and-departure-for-stop.html)
    ///
    /// - parameter stopID: The ID of the stop.
    /// - parameter tripID: The trip id of the arriving transit vehicle.
    /// - parameter serviceDate: The service date of the arriving transit vehicle.
    /// - parameter vehicleID: The vehicle id of the arriving transit vehicle (optional).
    /// - parameter stopSequence: the stop sequence index of the stop in the transit vehicle’s trip.
    /// - throws: ``APIError`` or other errors.
    /// - returns: The ``RESTAPIResponse`` for ``ArrivalDeparture``.
    public nonisolated func getTripArrivalDepartureAtStop(stopID: String, tripID: String, serviceDate: Date, vehicleID: String?, stopSequence: Int) async throws -> RESTAPIResponse<ArrivalDeparture> {
        let url = urlBuilder.getTripArrivalDepartureAtStop(stopID: stopID, tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopSequence: stopSequence)
        return try await getData(
            for: url,
            decodeRESTAPIResponseAs: ArrivalDeparture.self
        )
    }

    // MARK: - Trip Details
    /// Get extended details for a specific trip.
    ///
    /// - API Endpoint: `/api/where/trip-details/{id}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/trip-details.html)
    ///
    /// - parameter tripID: The ID of the trip.
    /// - parameter vehicleID: Optional ID for the specific transit vehicle on this trip.
    /// - parameter serviceDate: The service date for this trip.
    /// - throws: ``APIError`` or other errors.
    /// - returns: The ``RESTAPIResponse`` for ``TripDetails``.
    public nonisolated func getTrip(tripID: String, vehicleID: String?, serviceDate: Date?) async throws -> RESTAPIResponse<TripDetails> {
        return try await getData(
            for: urlBuilder.getTrip(tripID: tripID, vehicleID: vehicleID, serviceDate: serviceDate),
            decodeRESTAPIResponseAs: TripDetails.self
        )
    }

    // MARK: - Search
    /// Search for routes within a region, by name
    ///
    /// - API Endpoint: `/api/where/routes-for-location.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/routes-for-location.html)
    ///
    /// - parameter query: Search query
    /// - parameter region: The circular region from which to return results.
    /// - throws: ``APIError`` or other errors.
    /// - returns: The ``RESTAPIResponse`` for [``Route``].
    public nonisolated func getRoute(query: String, region: CLCircularRegion) async throws -> RESTAPIResponse<[Route]> {
        return try await getData(
            for: urlBuilder.getRoute(query: query, region: region),
            decodeRESTAPIResponseAs: [Route].self
        )
    }

    /// Retrieve the set of stops serving a particular route, including groups by direction of travel.
    ///
    /// The `stops-for-route` method first and foremost provides a method for retrieving the set of stops
    /// that serve a particular route. In addition to the full set of stops, we provide various
    /// "stop groupings" that are used to group the stops into useful collections. Currently, the main
    /// grouping provided organizes the set of stops by direction of travel for the route. Finally,
    /// this method also returns a set of polylines that can be used to draw the path traveled by the route.
    ///
    /// - API Endpoint: `/api/where/stops-for-route/{id}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/stops-for-route.html)
    ///
    /// - parameter id: The route ID.
    /// - throws: ``APIError`` or other errors.
    /// - returns: The ``RESTAPIResponse`` for ``StopsForRoute``.
    public nonisolated func getStopsForRoute(routeID: RouteID) async throws -> RESTAPIResponse<StopsForRoute> {
        return try await getData(
            for: urlBuilder.getStopsForRoute(id: routeID),
            decodeRESTAPIResponseAs: StopsForRoute.self
        )
    }

    // MARK: - Agencies
    /// Retrieves a list of agencies with known coverage areas for the current region.
    ///
    /// - throws: ``APIError`` or other errors.
    /// - returns: The ``RESTAPIResponse`` for [``AgencyWithCoverage``].
    public nonisolated func getAgenciesWithCoverage() async throws -> RESTAPIResponse<[AgencyWithCoverage]> {
        return try await getData(
            for: urlBuilder.getAgenciesWithCoverage(),
            decodeRESTAPIResponseAs: [AgencyWithCoverage].self
        )
    }
}
