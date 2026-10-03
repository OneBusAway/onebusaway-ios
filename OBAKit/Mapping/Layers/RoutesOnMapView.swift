//
//  RoutesOnMapView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import SwiftUI

/// The routes serving the stops on screen, pushed from the Map sheet. Picking
/// one filters the map down to that route.
///
/// Route search already did this, but only for riders who knew a route's name
/// to type — a campus shuttle network rarely has names a rider would guess.
///
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/1414
struct RoutesOnMapView: View {

    @ObservedObject var model: MapSheetModel

    var body: some View {
        content
            .navigationTitle(Strings.routesOnMapTitle)
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        switch model.routeFilterContent {
        case .zoomedOut:
            EmptyStateView(title: Strings.routesOnMapZoomedOut, systemImage: "plus.magnifyingglass")
        case .noRoutes:
            EmptyStateView(title: Strings.routesOnMapEmpty, systemImage: AppSymbol.bus)
        case .routes(let routes):
            List(routes, id: \.id) { route in
                row(for: route)
            }
        }
    }

    private func row(for route: Route) -> some View {
        Button {
            model.selectRoute(route)
        } label: {
            HStack(spacing: 12) {
                RouteBadgeView(
                    routeShortName: route.shortName,
                    routeColor: Color(uiColor: route.color ?? ThemeColors.shared.brand),
                    routeTextColor: route.textColor.map { Color(uiColor: $0) },
                    size: 36
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(route.shortName)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let subtitle = subtitle(for: route) {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Strings.routesOnMapRowHint)
    }

    /// Long name and agency together: a shuttle's long name alone ("Campus Loop")
    /// doesn't say whose shuttle it is when two operators share the curb.
    private func subtitle(for route: Route) -> String? {
        let parts = [route.longName, route.agency?.name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
