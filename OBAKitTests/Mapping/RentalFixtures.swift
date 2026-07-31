//
//  RentalFixtures.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OTPKit

/// Builds `VehicleRental` values for tests.
///
/// These are decoded rather than constructed directly: OTPKit's `RentalVehicle`,
/// `VehicleRentalStation`, `FuelInfo`, and `VehicleType` expose only internal
/// memberwise initializers, so the sole cross-module entry point is
/// `VehicleRental.init(from:)`. Dictionaries are built and handed to
/// `Fixtures.dictionaryToModel`, which round-trips them through
/// `JSONSerialization` + `JSONDecoder` — the same convention `Fixtures.swift`
/// uses elsewhere. Decoding has the side benefit of exercising the same path
/// real payloads take, including `__typename` discrimination.
enum RentalFixtures {

    /// A free-floating rental vehicle. Pass `rangeMeters: nil, batteryPercent: nil`
    /// for a vehicle whose feed publishes no fuel data at all.
    ///
    /// `networkId: nil` omits `rentalNetwork` entirely — the shape a feed takes
    /// when it publishes no network block, which deep-link resolution must survive.
    static func vehicle(
        id: String = "v1",
        formFactor: String = "SCOOTER",
        propulsion: String? = "ELECTRIC",
        rangeMeters: Int? = nil,
        batteryPercent: Double? = nil,
        operative: Bool = true,
        lat: Double = 47.6,
        lon: Double = -122.3,
        networkId: String? = "lime_seattle",
        networkURL: String? = nil,
        rentalUris: [String: String]? = nil
    ) throws -> VehicleRental {
        var fuel: [String: Any] = [:]
        if let batteryPercent { fuel["percent"] = batteryPercent }
        if let rangeMeters { fuel["range"] = rangeMeters }
        let fuelValue: Any = fuel.isEmpty ? NSNull() : fuel

        var vehicleType: [String: Any] = ["formFactor": formFactor]
        if let propulsion {
            vehicleType["propulsionType"] = propulsion
        } else {
            vehicleType["propulsionType"] = NSNull()
        }

        var dictionary: [String: Any] = [
            "__typename": "RentalVehicle",
            "vehicleId": id,
            "name": "Default vehicle type",
            "lat": lat,
            "lon": lon,
            "allowPickupNow": true,
            "operative": operative,
            "rentalUris": rentalUris ?? NSNull(),
            "vehicleType": vehicleType,
            "fuel": fuelValue
        ]
        if let networkId {
            dictionary["rentalNetwork"] = ["networkId": networkId, "url": networkURL ?? NSNull()] as [String: Any]
        }
        return try Fixtures.dictionaryToModel(type: VehicleRental.self, dictionary: dictionary)
    }

    /// A non-powered vehicle: a pedal bike, with no `fuel` object at all.
    static func pedalBike(id: String = "b1") throws -> VehicleRental {
        try vehicle(id: id, formFactor: "BICYCLE", propulsion: "HUMAN", rangeMeters: nil, batteryPercent: nil)
    }

    /// A docked station. Stations never carry fuel data.
    static func station(
        id: String = "s1",
        vehiclesAvailable: Int? = 4,
        operative: Bool = true,
        lat: Double = 47.6,
        lon: Double = -122.3,
        networkId: String? = "lime_seattle"
    ) throws -> VehicleRental {
        var dictionary: [String: Any] = [
            "__typename": "VehicleRentalStation",
            "stationId": id,
            "name": "Pine St Station",
            "lat": lat,
            "lon": lon,
            "operative": operative
        ]
        if let vehiclesAvailable {
            dictionary["vehiclesAvailable"] = vehiclesAvailable
        } else {
            dictionary["vehiclesAvailable"] = NSNull()
        }
        if let networkId {
            dictionary["rentalNetwork"] = ["networkId": networkId, "url": NSNull()] as [String: Any]
        }
        return try Fixtures.dictionaryToModel(type: VehicleRental.self, dictionary: dictionary)
    }

    /// A snapshot with the fixed `fetchedAt` every rental test depends on for
    /// determinism — `Date()` is avoided deliberately.
    static func snapshot(
        added: [VehicleRental] = [],
        removed: [VehicleRental.ID] = [],
        updated: [VehicleRental] = []
    ) -> VehicleRentalSnapshot {
        VehicleRentalSnapshot(added: added, removed: removed, updated: updated, fetchedAt: Date(timeIntervalSince1970: 0))
    }
}
