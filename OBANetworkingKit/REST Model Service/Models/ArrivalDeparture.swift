//
//  ArrivalDeparture.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 11/3/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class ArrivalDeparture: NSObject, Decodable {
    let arrivalEnabled: Bool
    let blockTripSequence: Int
    let departureEnabled: Bool
    let distanceFromStop: Double
    let frequency: Frequency?
    let lastUpdated: Date
    let numberOfStopsAway: Int
    let predicted: Bool
    let predictedArrival: Date
    let predictedDeparture: Date
    let routeID: String
    let routeLongName: String?
    let routeShortName: String
    let scheduledArrival: Date
    let scheduledDeparture: Date
    let serviceDate: Date
    let situationIDs: [String]
    let status: String
    let stopID: String
    let stopSequence: Int
    let totalStopsInTrip: Int
    let tripHeadsign: String
    let tripID: String
    let tripStatus: TripStatus?
    let vehicleID: String

    private enum CodingKeys: String, CodingKey {
        case arrivalEnabled
        case blockTripSequence
        case departureEnabled
        case distanceFromStop
        case frequency
        case lastUpdated = "lastUpdateTime"
        case numberOfStopsAway
        case predicted
        case predictedArrival = "predictedArrivalTime"
        case predictedDeparture = "predictedDepartureTime"
        case routeID = "routeId"
        case routeLongName
        case routeShortName
        case scheduledArrival = "scheduledArrivalTime"
        case scheduledDeparture = "scheduledDepartureTime"
        case serviceDate
        case situationIDs = "situationIds"
        case status
        case stopID = "stopId"
        case stopSequence
        case totalStopsInTrip
        case tripHeadsign
        case tripID = "tripId"
        case tripStatus
        case vehicleID = "vehicleId"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        arrivalEnabled = try container.decode(Bool.self, forKey: .arrivalEnabled)
        blockTripSequence = try container.decode(Int.self, forKey: .blockTripSequence)
        departureEnabled = try container.decode(Bool.self, forKey: .departureEnabled)
        distanceFromStop = try container.decode(Double.self, forKey: .distanceFromStop)
        frequency = try? container.decode(Frequency.self, forKey: .frequency)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        numberOfStopsAway = try container.decode(Int.self, forKey: .numberOfStopsAway)
        predicted = try container.decode(Bool.self, forKey: .predicted)
        predictedArrival = try container.decode(Date.self, forKey: .predictedArrival)
        predictedDeparture = try container.decode(Date.self, forKey: .predictedDeparture)
        routeID = try container.decode(String.self, forKey: .routeID)
        routeLongName = ModelHelpers.nilifyBlankValue((try? container.decode(String.self, forKey: .routeLongName)) ?? "")
        routeShortName = try container.decode(String.self, forKey: .routeShortName)
        scheduledArrival = try container.decode(Date.self, forKey: .scheduledArrival)
        scheduledDeparture = try container.decode(Date.self, forKey: .scheduledDeparture)
        serviceDate = try container.decode(Date.self, forKey: .serviceDate)
        situationIDs = try container.decode([String].self, forKey: .situationIDs)
        status = try container.decode(String.self, forKey: .status)
        stopID = try container.decode(String.self, forKey: .stopID)
        stopSequence = try container.decode(Int.self, forKey: .stopSequence)
        totalStopsInTrip = try container.decode(Int.self, forKey: .totalStopsInTrip)
        tripHeadsign = try container.decode(String.self, forKey: .tripHeadsign)
        tripID = try container.decode(String.self, forKey: .tripID)
        tripStatus = try? container.decode(TripStatus.self, forKey: .tripStatus)
        vehicleID = try container.decode(String.self, forKey: .vehicleID)
    }
}
