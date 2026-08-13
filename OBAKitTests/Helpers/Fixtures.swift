//
//  Fixtures.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
@testable import OBAKitCore

// swiftlint:disable force_try

class Fixtures {

    private class var testBundle: Bundle {
        Bundle(for: self)
    }

    /// Converts the specified dictionary to a model object of type `T`.
    /// - Parameters:
    ///   - type: The model type to which the dictionary will be converted.
    ///   - dictionary: The data
    /// - Returns: A model object
    class func dictionaryToModel<T>(type: T.Type, dictionary: [String: Any]) throws -> T where T: Decodable {
        let jsonData = try JSONSerialization.data(withJSONObject: dictionary, options: [])
        return try JSONDecoder().decode(type, from: jsonData)
    }

    /// Returns the path to the specified file in the test bundle.
    /// - Parameter fileName: The file name, e.g. "regions.json"
    class func path(to fileName: String) -> String {
        testBundle.path(forResource: fileName, ofType: nil)!
    }

    /// Encodes and decodes the provided `Codable` object. Useful for testing roundtripping.
    /// - Parameter type: The object type.
    /// - Parameter model: The object or objects.
    class func roundtripCodable<T>(type: T.Type, model: T) throws -> T where T: Codable {
        let encoded = try PropertyListEncoder().encode(model)
        let decoded = try PropertyListDecoder().decode(type, from: encoded)
        return decoded
    }

    /// Loads data from the specified file name, searching within the test bundle.
    /// - Parameter file: The file name to load data from. Example: `stop_data.pb`.
    class func loadData(file: String) -> Data {
        NSData(contentsOfFile: path(to: file))! as Data
    }

    class func loadRESTAPIPayload<T>(type: T.Type, fileName: String) throws -> T where T: Decodable {
        let data = loadData(file: fileName)
        let apiResponse = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<T>.self, from: data)
        return apiResponse.list
    }

    /// Builds an `ArrivalDeparture` from timestamps, defaulting the ~15 keys of
    /// decoder boilerplate that no test cares about. Times are seconds since the
    /// epoch; pass the predicted ones as `nil` to model a schedule-only trip.
    ///
    /// `stopSequence` selects `arrivalDepartureStatus`: 0 is `.departing`,
    /// anything else `.arriving`.
    class func arrivalDeparture(
        predicted: Bool = true,
        scheduledArrival: Int = 1_700_000_000,
        predictedArrival: Int? = nil,
        scheduledDeparture: Int = 1_700_000_000,
        predictedDeparture: Int? = nil,
        stopSequence: Int = 5
    ) throws -> ArrivalDeparture {
        var dictionary: [String: Any] = [
            "arrivalEnabled": true,
            "blockTripSequence": 1,
            "departureEnabled": true,
            "distanceFromStop": 100.0,
            "lastUpdateTime": scheduledArrival,
            "numberOfStopsAway": 1,
            "predicted": predicted,
            "routeId": "route_1",
            "scheduledArrivalTime": scheduledArrival,
            "scheduledDepartureTime": scheduledDeparture,
            "serviceDate": scheduledArrival,
            "situationIds": [],
            "status": "SCHEDULED",
            "stopId": "stop_1",
            "stopSequence": stopSequence,
            "tripId": "trip_1",
            "vehicleId": "vehicle_1"
        ]
        if let predictedArrival { dictionary["predictedArrivalTime"] = predictedArrival }
        if let predictedDeparture { dictionary["predictedDepartureTime"] = predictedDeparture }

        return try dictionaryToModel(type: ArrivalDeparture.self, dictionary: dictionary)
    }

    class func loadAlarm(id: String = "1234567890", region: String = "1") throws -> Alarm {
        return try dictionaryToModel(type: Alarm.self, dictionary: ["url": String(format: "https://alerts.example.com/regions/%@/alarms/%@", region, id)])
    }

    class func loadSomeStops() throws -> [Stop] {
        try loadRESTAPIPayload(type: [Stop].self, fileName: "stops_for_location_seattle.json")
    }

    class func loadSomeRegions() throws -> [Region] {
        try loadRESTAPIPayload(type: [Region].self, fileName: "regions-v3.json")
    }

    class var customMinneapolisRegion: Region {
        let coordinateRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 44.9778, longitude: -93.2650), latitudinalMeters: 1000.0, longitudinalMeters: 1000.0)

        return Region(name: "Custom Region", OBABaseURL: URL(string: "http://www.example.com")!, coordinateRegion: coordinateRegion, contactEmail: "contact@example.com")
    }

    class var customRegionWithSidecarAndUmami: Region {
        let coordinateRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 44.9778, longitude: -93.2650), latitudinalMeters: 1000.0, longitudinalMeters: 1000.0)

        return Region(
            name: "Custom Region",
            OBABaseURL: URL(string: "http://www.example.com")!,
            coordinateRegion: coordinateRegion,
            contactEmail: "contact@example.com",
            sidecarBaseURL: URL(string: "https://obaco.example.com")!,
            umamiAnalytics: UmamiAnalyticsConfig(url: URL(string: "https://analytics.example.com")!, id: "site-uuid-123"))
    }

    class var pugetSoundRegion: Region {
        let regions = try! loadSomeRegions()
        return regions[1]
    }

    class var tampaRegion: Region {
        let regions = try! loadSomeRegions()
        return regions[0]
    }

    class func stubAllAgencyAlerts(dataLoader: MockDataLoader) {
        let agencyAlertsData = loadData(file: "puget_sound_alerts.pb")
        dataLoader.mock(data: agencyAlertsData) { (request) -> Bool in
            request.url!.absoluteString.contains("/api/gtfs_realtime/alerts-for-agency")
            || request.url!.absoluteString.contains("alerts.pb")
        }
    }

    class func createRoute(id: String) throws -> Route {
        let dictionary: [String: Any] = [
            "agencyId": "test_agency",
            "id": id,
            "shortName": "1",
            "type": 3
        ]
        return try dictionaryToModel(type: Route.self, dictionary: dictionary)
    }
}
