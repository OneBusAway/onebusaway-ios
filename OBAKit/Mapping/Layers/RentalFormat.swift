//
//  RentalFormat.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import OBAKitCore
import OTPKit

/// Shared rider-facing formatting for rental entities, used by the detail sheet,
/// the cluster list, and the map annotation's fuel label.
enum RentalFormat {
    /// Cached: a fresh MKDistanceFormatter per row per render is waste.
    static let distanceFormatter = MKDistanceFormatter()

    /// A second formatter for space-constrained surfaces. The default style spells
    /// the unit out — 5,470 m renders as "3.4 miles" under en_US, where this one
    /// gives "3.4 mi". Only the abbreviated form fits under a map pin. The detail
    /// sheet's spelled-out rendering is deliberate, so the two coexist rather than
    /// one being mutated in place.
    static let abbreviatedDistanceFormatter: MKDistanceFormatter = {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter
    }()

    /// Straight-line walk estimate at the app's default walking speed.
    /// Nil beyond 10 km — a "119 min walk" line is noise, not information.
    static func walkTimeText(from userLocation: CLLocation?, to coordinate: CLLocationCoordinate2D) -> String? {
        guard let userLocation else { return nil }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let meters = userLocation.distance(from: target)
        guard meters.isFinite, meters < 10_000 else { return nil }

        let minutes = max(1, Int((meters / WalkingSpeed.defaultMetersPerSecond / 60).rounded()))
        // `localizedStringWithFormat`: plural forms live in Localizable.stringsdict,
        // and `String(format:)` only ever reaches the root rule's one/other.
        return String.localizedStringWithFormat(
            OBALoc("rental_detail.walk_time_fmt", value: "%d min walk", comment: "Estimated walking time to a rental vehicle. Plural forms live in Localizable.stringsdict; the value above is only the not-found fallback."),
            minutes
        )
    }

    /// "%d available" beneath a station marker's title and in its VoiceOver label.
    static func stationAvailableText(_ count: Int) -> String {
        String.localizedStringWithFormat(
            OBALoc("rental_annotation.vehicles_available_fmt", value: "%d available", comment: "Number of rental vehicles available at a station. Plural forms live in Localizable.stringsdict; the value above is only the not-found fallback."),
            count
        )
    }

    // MARK: - Station stock

    /// What a station holds, as far as its typed availability says.
    enum StationStock: Equatable {
        case bikes
        case scooters
        /// A mix of form factors, or a feed that publishes no typed breakdown.
        case unknown
    }

    /// Classifies a station's stock from `availableVehicles.byType`. Only a
    /// breakdown whose every entry agrees earns a specific answer: a station
    /// labeled "Bikes" while it holds scooters is the bug this replaces.
    static func stock(of station: VehicleRentalStation) -> StationStock {
        guard let byType = station.availableVehicles?.byType, !byType.isEmpty else { return .unknown }
        let formFactors = byType.map(\.vehicleType.formFactor)
        if formFactors.allSatisfy({ $0?.isBicycle == true }) { return .bikes }
        if formFactors.allSatisfy({ $0?.isScooter == true }) { return .scooters }
        return .unknown
    }

    /// The label under a station's vehicle count in the detail sheet.
    static func stationVehiclesLabel(for station: VehicleRentalStation) -> String {
        switch stock(of: station) {
        case .bikes:
            return OBALoc("rental_detail.bikes_available", value: "Bikes", comment: "Label for the number of bikes available at a station")
        case .scooters:
            return OBALoc("rental_detail.scooters_available", value: "Scooters", comment: "Label for the number of scooters available at a station that only holds scooters")
        case .unknown:
            return OBALoc("rental_detail.vehicles_available", value: "Available", comment: "Label for the number of rental vehicles available at a station whose vehicle types are mixed or unknown")
        }
    }

    /// Feeds do send values outside 0...1. Clamp rather than render "120%" or "-10%".
    /// The pin, the detail sheet, and the cluster list all go through here.
    static func batteryText(_ percent: Double) -> String {
        let clamped = min(max(percent, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// The text rendered beneath a rental map pin: battery percent when the feed
    /// provides it, else remaining range, else nothing.
    ///
    /// The percent-first ordering matches the mockup, but the range fallback is the
    /// common path in practice: on the launch feed `percent` is null across the
    /// whole fleet while `range` is populated.
    static func fuelLabelText(for rental: VehicleRental) -> String? {
        guard case .vehicle(let vehicle) = rental, let fuel = vehicle.fuel else { return nil }

        if let percent = fuel.percent {
            return batteryText(percent)
        }

        if let range = fuel.range {
            return abbreviatedDistanceFormatter.string(fromDistance: CLLocationDistance(range))
        }

        return nil
    }

    // MARK: - Labels and spoken forms

    static var rangeLabel: String {
        OBALoc("rental_detail.range", value: "Range", comment: "Label for a rental vehicle's estimated remaining range")
    }

    static var batteryLabel: String {
        OBALoc("rental_detail.battery", value: "Battery", comment: "Label for a rental vehicle's battery charge")
    }

    /// Spells the unit out ("3.4 miles", never "3.4 mi"): VoiceOver reads an
    /// abbreviation letter by letter, or not at all.
    private static let spokenDistanceFormatter: MKDistanceFormatter = {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .full
        return formatter
    }()

    static func spokenRangeText(_ meters: Int) -> String {
        spokenDistanceFormatter.string(fromDistance: CLLocationDistance(meters))
    }

    /// The percent sign is the unit word: VoiceOver reads "80%" as "80 percent".
    static func spokenBatteryText(_ percent: Double) -> String {
        batteryText(percent)
    }

    /// The fuel figure as VoiceOver should hear it, named: "Battery 80%" or
    /// "Range 3.4 miles". Same precedence as `fuelLabelText`, so the spoken and
    /// drawn figures always describe the same quantity.
    static func spokenFuelText(for rental: VehicleRental) -> String? {
        guard case .vehicle(let vehicle) = rental, let fuel = vehicle.fuel else { return nil }

        if let percent = fuel.percent {
            return "\(batteryLabel) \(spokenBatteryText(percent))"
        }

        if let range = fuel.range {
            return "\(rangeLabel) \(spokenRangeText(range))"
        }

        return nil
    }

    /// The VoiceOver label for a single rental marker, on either map surface:
    /// name, service state, then what is there — the station's count or the
    /// vehicle's fuel. Assigning a label replaces MapKit's title/subtitle default,
    /// so anything a sighted rider can read off the marker has to be in here.
    static func markerAccessibilityLabel(for rental: VehicleRental) -> String {
        var parts = [rental.displayLabel]

        if !rental.isOperative {
            parts.append(OBALoc("rental_detail.not_in_service", value: "Not in service", comment: "Shown for a rental vehicle or station that is not operative"))
        }

        switch rental {
        case .station(let station):
            if let available = station.vehiclesAvailableCount {
                parts.append(stationAvailableText(available))
            }
        case .vehicle:
            if let fuel = spokenFuelText(for: rental) {
                parts.append(fuel)
            }
        }

        return parts.joined(separator: ", ")
    }

    /// The VoiceOver label for a cluster marker: "4 vehicles here".
    static func clusterAccessibilityLabel(count: Int) -> String {
        // `localizedStringWithFormat`, not `String(format:)` — the latter resolves
        // `%#@count@` against the root plural rule, so VoiceOver would read the
        // `one`/`other` form for every count in ar, pl, and ru.
        String.localizedStringWithFormat(
            OBALoc("rental_cluster.title_fmt", value: "%d vehicles here", comment: "Title of the sheet listing the members of a rental cluster. Plural forms live in Localizable.stringsdict; the value above is only the not-found fallback."),
            count
        )
    }

    // MARK: - Open-in-app button

    /// Title and VoiceOver hint for the rental sheet's "Open in <operator>" button.
    ///
    /// The hint only promises the App Store when the opener can actually show it
    /// — that is, when the operator's App Store id is known. An unknown operator
    /// gets a generic title rather than a URL host or the bare word "app".
    struct OpenButtonCopy: Equatable {
        let title: String
        let hint: String?
    }

    static func openButtonCopy(for target: RentalDeepLink.Target) -> OpenButtonCopy {
        guard let name = target.operatorName, !name.isEmpty else {
            return OpenButtonCopy(
                title: OBALoc("rental_detail.open_rental_app", value: "Open rental app", comment: "Button opening a rental operator's app when the operator's name is unknown"),
                hint: nil
            )
        }

        let title = String(format: OBALoc("rental_detail.open_in_fmt", value: "Open in %@", comment: "Button opening the rental operator's app or website"), name)
        let hint = target.appStoreID.map { _ in
            String(format: OBALoc("rental_detail.open_in_hint_fmt", value: "Opens %@, or its App Store page if it isn't installed.", comment: "VoiceOver hint on the button opening a rental operator's app. %@ is the operator, e.g. Lime."), name)
        }
        return OpenButtonCopy(title: title, hint: hint)
    }
}
