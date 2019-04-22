//
//  VehicleStopModel.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/4/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import Foundation

/// Provides an abstraction to represent a vehicle arriving and departing from a stop, as seen at the end/beginning of a route.
@objc(OBAVehicleStopModel)
public class VehicleStopModel: NSObject {
    public let vehicleID: String?
    public fileprivate(set) var arrivalDepartures = [ArrivalDeparture]()

    private var _date: Date?
    public var date: Date {
        if _date == nil {
            _date = arrivalDepartures.sorted(by: { $0.arrivalDepartureDate > $1.arrivalDepartureDate }).last!.arrivalDepartureDate
        }
        return _date!
    }

    public init(vehicleID: String?) {
        self.vehicleID = vehicleID
        super.init()
    }
}

public extension Sequence where Element: ArrivalDeparture {
    func toVehicleStopModels() -> [VehicleStopModel] {
        var models = [String: VehicleStopModel]()

        for arrDep in self {
            let key = arrDep.vehicleID ?? NSUUID().uuidString
            let dictEntry = models[key, default: VehicleStopModel(vehicleID: arrDep.vehicleID)]
            dictEntry.arrivalDepartures.append(arrDep)
            models[key] = dictEntry
        }

        return Array(models.values).sorted(by: { $0.date < $1.date })
    }
}
