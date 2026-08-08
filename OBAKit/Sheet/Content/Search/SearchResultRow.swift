//
//  SearchResultRow.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import OBAKitCore

/// Builds `SearchListRow`s for disambiguation results, so the results sheet renders
/// through the same row view as the search list above it.
enum SearchResultRow {

    static func row(for result: Any, application: Application, onSelect: @escaping () -> Void) -> SearchListRow? {
        switch result {
        case let stop as Stop:
            return SearchListRow(
                kind: .searchResult(id: stop.id),
                title: stop.name,
                subtitle: stopSubtitle(application, stop),
                icon: .uiImage(Icons.stop),
                accessory: .disclosureIndicator,
                action: onSelect
            )

        case let route as Route:
            return SearchListRow(
                kind: .searchResult(id: route.id),
                title: route.shortName,
                subtitle: route.longName ?? route.agency.name,
                icon: .uiImage(Icons.route),
                accessory: .disclosureIndicator,
                action: onSelect
            )

        case let mapItem as MKMapItem:
            guard let title = mapItem.name ?? mapItem.placemark.title, !title.isEmpty else { return nil }
            return SearchListRow(
                kind: .placemark(mapItem),
                title: title,
                subtitle: SearchListRow.subtitleForMapItem(application, mapItem),
                icon: SearchListRow.systemImageForMapItem(mapItem),
                accessory: .disclosureIndicator,
                action: onSelect
            )

        case let vehicle as AgencyVehicle:
            guard let vehicleID = vehicle.vehicleID else { return nil }
            return SearchListRow(
                kind: .searchResult(id: vehicleID),
                title: vehicleID,
                subtitle: vehicle.agencyName,
                icon: .uiImage(Icons.busTransport),
                accessory: .disclosureIndicator,
                action: onSelect
            )

        default:
            return nil
        }
    }

    /// Direction plus distance from the user, mirroring what the placemark rows in
    /// the search list already show. Distance is dropped when there's no fix.
    private static func stopSubtitle(_ application: Application, _ stop: Stop) -> String? {
        var parts: [String] = []

        if let currentLocation = application.locationService.currentLocation {
            let distance = currentLocation.distance(from: CLLocation(latitude: stop.coordinate.latitude, longitude: stop.coordinate.longitude))
            parts.append(application.formatters.distanceFormatter.string(fromDistance: distance))
        }

        if let direction = Formatters.adjectiveFormOfCardinalDirection(stop.direction), !direction.isEmpty {
            parts.append(direction)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}
