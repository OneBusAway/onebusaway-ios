//
//  TripStopTime.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public class TripStopTime: NSObject, Decodable, HasReferences {

    /// Time, in seconds since the start of the service date, when the trip arrives at the specified stop.
    private let arrival: TimeInterval

    public private(set) var arrivalDate: Date!

    /// Time, in seconds since the start of the service date, when the trip arrives at the specified stop
    private let departure: TimeInterval

    public private(set) var departureDate: Date!

    /// The stop id of the stop visited during the trip
    public let stopID: StopID

    /// The stop visited during the trip.
    public private(set) var stop: Stop!

    var serviceDate: Date! {
        didSet {
            arrivalDate = Calendar.current.date(byAdding: .second, value: Int(arrival), to: serviceDate)
            departureDate = Calendar.current.date(byAdding: .second, value: Int(departure), to: serviceDate)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case arrival = "arrivalTime"
        case departure = "departureTime"
        case stopID = "stopId"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        arrival = try container.decode(TimeInterval.self, forKey: .arrival)
        departure = try container.decode(TimeInterval.self, forKey: .departure)
        stopID = try container.decode(String.self, forKey: .stopID)
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? TripStopTime else { return false }

        return
            arrival == rhs.arrival &&
            departure == rhs.departure &&
            stopID == rhs.stopID
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(arrival)
        hasher.combine(departure)
        hasher.combine(stopID)
        return hasher.finalize()
    }

    public func loadReferences(_ references: References) {
        stop = references.stopWithID(stopID)!
    }
}
