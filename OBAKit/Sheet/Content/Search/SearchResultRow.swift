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

    /// The whole disambiguation list, including the in-place progress swap for a
    /// vehicle whose details are being fetched. A static function rather than a
    /// computed property on the view so the mapping can be asserted without a view
    /// host — the same shape `RouteStopsRow.rows(from:)` uses.
    static func rows(
        for results: [Any],
        loadingVehicleID: String?,
        application: Application,
        onSelectVehicle: @escaping (String) -> Void,
        onSelect: @escaping (Any) -> Void
    ) -> [SearchListRow] {
        results.compactMap { result in
            if let vehicle = result as? AgencyVehicle, let vehicleID = vehicle.vehicleID {
                // Vehicles need a second request before they can be routed, so the
                // row shows progress in place instead of navigating immediately.
                if loadingVehicleID == vehicleID {
                    return SearchListRow(kind: .loading, title: vehicleID, icon: .system("bus"))
                }
                return row(for: result, application: application) { onSelectVehicle(vehicleID) }
            }

            return row(for: result, application: application) { onSelect(result) }
        }
    }

    /// The one inline error row the results sheet shows, from either of the two things
    /// that can fail there: looking a vehicle's details up, or resolving any other
    /// tapped row. A failed resolve used to be dropped on the floor, which left the
    /// tapped row doing nothing at all with no explanation.
    ///
    /// Rendered inline rather than as a modal alert: the sheet is already the user's
    /// context, and a bulletin over it hides what failed. `SearchListRowView.errorRow`
    /// shows a retry badge and enables the row only when there's an action, so a
    /// failure the user can re-attempt isn't a dead end.
    ///
    /// Static, and taking the state rather than reading it, so the choice of which
    /// failure wins and whether a retry is offered is assertable without a view host.
    static func inlineErrorRow(
        vehicleError: Error?,
        failedVehicleID: String?,
        selectionError: Error?,
        failedResult: Any?,
        onRetryVehicle: @escaping (String) -> Void,
        onRetrySelect: @escaping (Any) -> Void
    ) -> SearchListRow? {
        if let vehicleError {
            return errorRow(
                message: vehicleError.localizedDescription,
                retry: failedVehicleID.map { vehicleID in { onRetryVehicle(vehicleID) } }
            )
        }

        if let selectionError {
            return errorRow(
                message: selectionError.localizedDescription,
                retry: failedResult.map { result in { onRetrySelect(result) } }
            )
        }

        return nil
    }

    private static func errorRow(message: String, retry: (() -> Void)?) -> SearchListRow {
        SearchListRow(
            kind: .error(message, systemImage: AppSymbol.error),
            title: message,
            subtitle: Strings.retry,
            icon: .system(AppSymbol.error),
            action: retry
        )
    }

    static func row(for result: Any, application: Application, onSelect: @escaping () -> Void) -> SearchListRow? {
        switch result {
        case let stop as Stop:
            return SearchListRow.stop(
                stop,
                application: application,
                kind: .searchResult(id: stop.id),
                onSelect: onSelect
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

}
