//
//  RouteStopsSheetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import MapKit
import OBAKitCore

/// One row of the route-stops list. A plain value so the mapping — including the
/// direction formatting and the unresolved-stops case — is testable without a view.
struct RouteStopsRow: Identifiable {
    let stopID: Stop.ID
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D

    var id: Stop.ID { stopID }

    /// `StopsForRoute.stops` is an implicitly-unwrapped optional filled in by
    /// `HasReferences`; an unresolved payload yields no rows rather than a crash.
    static func rows(from stopsForRoute: StopsForRoute) -> [RouteStopsRow] {
        (stopsForRoute.stops ?? []).map { stop in
            RouteStopsRow(
                stopID: stop.id,
                title: stop.name,
                subtitle: Formatters.adjectiveFormOfCardinalDirection(stop.direction) ?? "",
                coordinate: stop.coordinate
            )
        }
    }
}

/// `AppSheetRoute.routeStops` — the stop list for a searched route, opening at the
/// medium detent so the polyline stays on screen. Native replacement for
/// `RouteStopsViewController`.
///
/// The polyline itself is drawn by `MapPanelRootView` and dropped when this route
/// leaves the sheet stack — the sheet doesn't clear the map on its own way out. See
/// `MapSearchDisplayModel.owner`.
struct RouteStopsSheetView: View {
    let stopsForRoute: StopsForRoute

    /// Only used to pan the map alongside the list; the drawn route's lifetime is
    /// not this view's business.
    let displayModel: MapSearchDisplayModel

    @EnvironmentObject var coordinator: SheetCoordinator<AppSheetRoute>
    @Environment(\.dismiss) private var dismiss

    private var rows: [RouteStopsRow] { RouteStopsRow.rows(from: stopsForRoute) }

    var body: some View {
        NavigationStack {
            List(rows) { row in
                Button {
                    // Keep the map in step with the list — something the UIKit
                    // controller can't do, since it has no handle on the map.
                    displayModel.focus(coordinate: row.coordinate)
                    coordinator.push(.stopDetails(stopID: row.stopID))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                            if !row.subtitle.isEmpty {
                                Text(row.subtitle)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color(uiColor: ThemeColors.shared.brand))
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .searchListChrome()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(stopsForRoute.route?.shortName ?? "")
                            .font(.headline)
                        if let subtitle = routeSubtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(Strings.close) { dismiss() }
                }
            }
        }
        .searchSheetBackground()
    }

    private var routeSubtitle: String? {
        guard let route = stopsForRoute.route else { return nil }
        return route.longName ?? route.agency.name
    }
}
