//
//  ObacoModelService.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/9/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import OBAModelKit

/// Retrieves data and converts it into models from the Obaco/alerts API server
///
/// This is the service responsible for supplementary features: alarms, regional alerts, and weather.
@objc(OBAObacoModelService)
public class ObacoModelService: ModelService {
    private let apiService: ObacoService

    /// Create an ObacoModelService object.
    ///
    /// - Parameters:
    ///   - apiService: The API service object
    ///   - dataQueue: An operation queue
    public init(apiService: ObacoService, dataQueue: OperationQueue) {
        self.apiService = apiService
        super.init(dataQueue: dataQueue)
    }

    // MARK: - Weather

    /// Create an operation to fetch the weather forecast for the specified region.
    ///
    /// - Parameter regionID: The region identifier for which to fetch the weather. This is the `Region.regionIdentifier` field.
    /// - Returns: A model operation that returns a `Weather` object.
    @objc public func getWeather(regionID: String) -> WeatherModelOperation {
        let service = apiService.getWeather(regionID: regionID)
        let data = WeatherModelOperation()

        transferData(from: service, to: data) { [unowned service, unowned data] in
            data.apiOperation = service
        }
        return data
    }

    // MARK: - Alarms

    /// Create a model operation to add a push notification alarm.
    ///
    /// - Parameters:
    ///   - secondsBefore: Number of seconds before the trip departure time that the alarm should be triggered.
    ///   - stopID: The stop ID where the trip occurs.
    ///   - tripID: The trip's ID.
    ///   - serviceDate: The service date for the trip.
    ///   - vehicleID: The vehicle ID for the trip.
    ///   - stopSequence: The stop sequence for the trip.
    ///   - userPushID: The user's unique push ID.
    /// - Returns: A model operation that returns an `Alarm` object.
    @objc public func postAlarm(secondsBefore: TimeInterval, stopID: String, tripID: String, serviceDate: Int64, vehicleID: String, stopSequence: Int, userPushID: String) -> AlarmModelOperation {
        let service = apiService.postAlarm(secondsBefore: secondsBefore, stopID: stopID, tripID: tripID, serviceDate: serviceDate, vehicleID: vehicleID, stopSequence: stopSequence, userPushID: userPushID)
        let data = AlarmModelOperation()

        transferData(from: service, to: data) { [unowned service, unowned data] in
            data.apiOperation = service
        }

        return data
    }

    /// Cancels the specified alarm.
    ///
    /// - Parameter alarm: The alarm to cancel.
    /// - Returns: A network operation that will cancel the alarm.
    @objc public func deleteAlarm(alarm: Alarm) -> NetworkOperation {
        return apiService.deleteAlarm(url: alarm.url)
    }

    // MARK: - Vehicles

    /// A search for vehicles matching the passed-in query string.
    ///
    /// - Parameter query: The vehicle query. e.g. "1234" will match vehicles "1_1234", "2_1234", etc.
    /// - Returns: A model operation that retrieves a list of matching vehicles.
    @objc public func getVehicles(matching query: String) -> AgencyVehicleModelOperation {
        let service = apiService.getVehicles(matching: query)
        let data = AgencyVehicleModelOperation()

        transferData(from: service, to: data) { [unowned service, unowned data] in
            data.apiOperation = service
        }

        return data
    }
}
