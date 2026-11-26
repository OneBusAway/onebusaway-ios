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

    /// Retrieves stops matching `query` within `region`.
    ///
    /// Prefer this over ``getStops(circularRegion:query:)`` for stop-number search:
    /// the circular overload caps radius at 15 km and can miss same-code stops
    /// elsewhere in a multi-agency region (#1432).
    ///
    /// - API Endpoint: `/api/where/stops-for-location.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/stops-for-location.html)
    ///
    /// - parameter region: A coordinate region from which to search for stops.
    /// - parameter query: A search query for a specific stop code.
    /// - throws: ``APIError`` or other errors.
    /// - returns: The ``RESTAPIResponse`` for [``Stop``].
    public nonisolated func getStops(region: MKCoordinateRegion, query: String) async throws -> RESTAPIResponse<[Stop]> {
        return try await getData(
            for: urlBuilder.getStops(region: region, query: query),
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
    public nonisolated func getArrivalsAndDeparturesForStop(
        id: StopID,
        minutesBefore: UInt,
        minutesAfter: UInt,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> RESTAPIResponse<StopArrivals> {
        let url = urlBuilder.getArrivalsAndDeparturesForStop(id: id, minutesBefore: minutesBefore, minutesAfter: minutesAfter)
        do {
            return try await getData(
                for: url,
                decodeRESTAPIResponseAs: StopArrivals.self,
                cachePolicy: cachePolicy
            )
        } catch let error as APIError where error.isNullResponseBody {
            return try await noServiceArrivals(stopID: id, nullBodyError: error, cachePolicy: cachePolicy)
        }
    }

    /// `getArrivalsAndDeparturesForStop`, also returning the response body, so a
    /// caller can save it and show it again with `decodeKeptBody(_:from:)`
    /// while offline. The body is `nil`
    /// when the server answered `null` and the reply was rebuilt as a
    /// no-service day: there is nothing worth saving.
    public nonisolated func getArrivalsAndDeparturesForStopKeepingBody(
        id: StopID,
        minutesBefore: UInt,
        minutesAfter: UInt
    ) async throws -> (RESTAPIResponse<StopArrivals>, Data?) {
        let url = urlBuilder.getArrivalsAndDeparturesForStop(id: id, minutesBefore: minutesBefore, minutesAfter: minutesAfter)
        do {
            return try await getDataKeepingBody(for: url, decodeRESTAPIResponseAs: StopArrivals.self, using: decoder)
        } catch let error as APIError where error.isNullResponseBody {
            return (try await noServiceArrivals(stopID: id, nullBodyError: error, cachePolicy: .useProtocolCachePolicy), nil)
        }
    }

    /// Decodes a body kept by one of the `KeepingBody` calls. The body must
    /// come from this service's region: references resolve against it.
    public nonisolated func decodeKeptBody<T: Decodable>(_ type: T.Type, from body: Data) throws -> RESTAPIResponse<T> {
        try decoder.decode(RESTAPIResponse<T>.self, from: body)
    }

    /// Recovers from an arrivals response whose body is the literal `null`.
    ///
    /// Java OBA servers older than 2.7.2 send that body (HTTP 200) for two
    /// different cases, and the body alone can't tell them apart:
    ///
    /// - The stop doesn't exist (#1331).
    /// - The stop exists, but none of its routes run on the requested day. For
    ///   example, a weekday-only stop opened on a Saturday: Puget Sound stop
    ///   `1_39810` on 2026-11-15, OneBusAway/maglev#2102.
    ///
    /// The same body also comes from a server that crashed while building the
    /// reply (onebusaway-application-modules#461), with service running.
    ///
    /// To tell a missing stop from the rest, fetch the stop. If the server has
    /// it, build what maglev returns on a no-service day: the stop with no
    /// arrivals and departures. Callers then show their neutral empty state
    /// ("No departures in the next N minutes"), which claims nothing about the
    /// day's service. In the crash case this hides real departures; the `null`
    /// itself is still logged at error level by `APIService+GetData`.
    ///
    /// If the server has no such stop, rethrow `nullBodyError`, so callers keep
    /// their missing-stop handling (`APIError.indicatesMissingStop`). If the
    /// stop fetch fails for another reason, throw that error, which reads as a
    /// transient failure, rather than tell the rider the stop is gone.
    private nonisolated func noServiceArrivals(
        stopID: StopID,
        nullBodyError: APIError,
        cachePolicy: URLRequest.CachePolicy
    ) async throws -> RESTAPIResponse<StopArrivals> {
        let stopData: Data
        let httpResponse: HTTPURLResponse
        do {
            (stopData, httpResponse) = try await getData(for: urlBuilder.getStop(stopID: stopID), cachePolicy: cachePolicy)
        } catch let stopError as APIError where stopError.indicatesMissingStop {
            throw nullBodyError
        }

        // Only a body that says "no such stop" may read as a missing stop. Anything
        // else that isn't a usable stop (a captive portal's HTML, a malformed body,
        // an envelope carrying some other error code) is a transient failure, and
        // must not tell the rider their bookmark is broken.
        let unusableStopResponse = APIError.invalidContentType(
            originalError: nil,
            expectedContentType: "json",
            actualContentType: httpResponse.contentType
        )
        guard httpResponse.hasJSONContentType else { throw unusableStopResponse }

        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: stopData, options: .fragmentsAllowed)
        } catch {
            throw unusableStopResponse
        }
        if json is NSNull { throw nullBodyError }
        guard var root = json as? [String: Any] else { throw unusableStopResponse }

        guard
            var payload = root["data"] as? [String: Any],
            let stopEntry = payload["entry"] as? [String: Any]
        else {
            let code = root["code"] as? Int
            if code == nil || code == 200 || code == 404 { throw nullBodyError }
            throw unusableStopResponse
        }
        guard let resolvedStopID = stopEntry["id"] as? String else { throw unusableStopResponse }

        var references = payload["references"] as? [String: Any] ?? [:]
        references["stops"] = (references["stops"] as? [[String: Any]] ?? []) + [stopEntry]
        payload["references"] = references
        payload["entry"] = [
            "arrivalsAndDepartures": [Any](),
            "nearbyStopIds": [Any](),
            "situationIds": [Any](),
            "stopId": resolvedStopID
        ]
        root["data"] = payload

        // Info, not error: `APIService+GetData` has already logged the `null` itself at
        // error level, so the server problem shows up without doubling the line on
        // every poll of a stop that simply has no service today.
        logger.info("Arrivals for \(stopID, privacy: .public) returned 'null' but the stop exists; showing no departures. This is a server bug: either the stop has no service today or the server failed to build the reply.")

        let synthesized = try JSONSerialization.data(withJSONObject: root)
        let decoded = try decoder.decode(RESTAPIResponse<StopArrivals>.self, from: synthesized)
        stampServerClock(on: decoded, from: httpResponse)
        return decoded
    }

    /// The arrival a deep link (an alarm, a shared trip) names.
    public nonisolated func getTripArrivalDepartureAtStop(deepLink: ArrivalDepartureDeepLink) async throws -> RESTAPIResponse<ArrivalDeparture> {
        try await getTripArrivalDepartureAtStop(
            stopID: deepLink.stopID,
            tripID: deepLink.tripID,
            serviceDate: deepLink.serviceDate,
            vehicleID: deepLink.vehicleID,
            stopSequence: deepLink.stopSequence
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
    public nonisolated func getTripArrivalDepartureAtStop(
        stopID: String,
        tripID: String,
        serviceDate: Date,
        vehicleID: String?,
        stopSequence: Int,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> RESTAPIResponse<ArrivalDeparture> {
        let url = urlBuilder.getTripArrivalDepartureAtStop(stopID: stopID, tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopSequence: stopSequence)
        return try await getData(
            for: url,
            decodeRESTAPIResponseAs: ArrivalDeparture.self,
            cachePolicy: cachePolicy
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
    public nonisolated func getTrip(
        tripID: String,
        vehicleID: String?,
        serviceDate: Date?,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async throws -> RESTAPIResponse<TripDetails> {
        return try await getData(
            for: urlBuilder.getTrip(tripID: tripID, vehicleID: vehicleID, serviceDate: serviceDate),
            decodeRESTAPIResponseAs: TripDetails.self,
            cachePolicy: cachePolicy
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

    /// Performs a local search and returns matching results
    ///
    /// - parameter query: The term for which to search.
    /// - parameter region: The coordinate region in which to search.
    /// - throws: MapKit errors.
    /// - returns: Search results from MapKit.
    public nonisolated func getPlacemarks(query: String, region: MKCoordinateRegion) async throws -> MKLocalSearch.Response {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region

        let search = MKLocalSearch(request: request)
        let response = try await search.start()

        return response
    }

    // MARK: - Shapes
    /// Retrieve a shape (the path traveled by a transit vehicle) by id
    ///
    /// - API Endpoint: `/api/where/shape/{id}.json`
    /// - [View REST API documentation](http://developer.onebusaway.org/modules/onebusaway-application-modules/current/api/where/methods/shape.html)
    ///
    /// - parameter id: The ID of the shape to retrieve.
    /// - throws: ``APIError`` or other errors.
    /// - returns: The ``RESTAPIResponse`` for [``PolylineEntity``]. 
    public nonisolated func getShape(id: String) async throws -> RESTAPIResponse<PolylineEntity> {
        return try await getData(
            for: urlBuilder.getShape(id: id),
            decodeRESTAPIResponseAs: PolylineEntity.self
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

    // MARK: - Schedules

    /// Retrieves a full schedule for a route for a particular day.
    ///
    /// - API Endpoint: `/api/where/schedule-for-route/{id}.json`
    /// - [View REST API documentation](https://developer.onebusaway.org/api/where/methods/schedule-for-route)
    ///
    /// - Parameters:
    ///   - routeID: The route ID.
    ///   - date: Optional date for which to retrieve the schedule. Defaults to current date.
    ///   - timeZone: Time zone used to resolve the civil day for `date`. Defaults to `.current`.
    /// - throws: ``APIError`` or other errors.
    /// - returns: The ``RESTAPIResponse`` for ``ScheduleForRoute``.
    public nonisolated func getScheduleForRoute(
        routeID: RouteID,
        date: Date? = nil,
        timeZone: TimeZone = .current
    ) async throws -> RESTAPIResponse<ScheduleForRoute> {
        return try await getData(
            for: urlBuilder.getScheduleForRoute(id: routeID, date: date, timeZone: timeZone),
            decodeRESTAPIResponseAs: ScheduleForRoute.self
        )
    }

    /// Retrieves a schedule for a stop for a particular day.
    ///
    /// - API Endpoint: `/api/where/schedule-for-stop/{id}.json`
    /// - [View REST API documentation](https://developer.onebusaway.org/api/where/methods/schedule-for-stop)
    ///
    /// - Parameters:
    ///   - stopID: The stop ID.
    ///   - date: Optional date for which to retrieve the schedule. Defaults to current date.
    ///   - timeZone: Time zone used to resolve the civil day for `date`. Defaults to `.current`.
    /// - throws: ``APIError`` or other errors.
    /// - returns: The ``RESTAPIResponse`` for ``ScheduleForStop``.
    public nonisolated func getScheduleForStop(
        stopID: StopID,
        date: Date? = nil,
        timeZone: TimeZone = .current
    ) async throws -> RESTAPIResponse<ScheduleForStop> {
        return try await getData(
            for: urlBuilder.getScheduleForStop(id: stopID, date: date, timeZone: timeZone),
            decodeRESTAPIResponseAs: ScheduleForStop.self
        )
    }

    /// `getScheduleForStop` for the server's today, also returning the
    /// response body, so a caller can save it and decode it again with
    /// `decodeKeptBody(_:from:)` while offline.
    public nonisolated func getScheduleForStopKeepingBody(stopID: StopID) async throws -> (RESTAPIResponse<ScheduleForStop>, Data) {
        try await getDataKeepingBody(
            for: urlBuilder.getScheduleForStop(id: stopID, date: nil),
            decodeRESTAPIResponseAs: ScheduleForStop.self,
            using: decoder
        )
    }

    // MARK: - Helpers
    nonisolated func getData<T: Decodable>(
        for url: URL,
        decodeAs decodeType: T.Type,
        timeoutPolicy: RequestTimeoutPolicy = .interactive
    ) async throws -> T {
        return try await getData(for: url, decodeAs: decodeType, using: self.decoder, timeoutPolicy: timeoutPolicy)
    }

    nonisolated func getData<T: Decodable>(
        for url: URL,
        decodeRESTAPIResponseAs decodeType: T.Type,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        timeoutPolicy: RequestTimeoutPolicy = .interactive
    ) async throws -> RESTAPIResponse<T> {
        return try await getData(for: url, decodeRESTAPIResponseAs: decodeType, using: self.decoder, cachePolicy: cachePolicy, timeoutPolicy: timeoutPolicy)
    }
}
