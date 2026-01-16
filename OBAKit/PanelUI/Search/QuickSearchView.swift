//
//  QuickSearchView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Shows quick search options (Route, Address, Stop, Vehicle) when user types text
struct QuickSearchView: View {
    let searchText: String
    let isVehicleSearchAvailable: Bool
    let brandColor: Color
    let onSearchTypeSelected: (SearchType, String) -> Void

    // Localized strings matching SearchInteractor
    private let routePrefix = OBALoc("search_interactor.quick_search.route_prefix", value: "Route:", comment: "Quick search prefix for Route.")
    private let addressPrefix = OBALoc("search_interactor.quick_search.address_prefix", value: "Address:", comment: "Quick search prefix for Address.")
    private let stopPrefix = OBALoc("search_interactor.quick_search.stop_prefix", value: "Stop:", comment: "Quick search prefix for Stop.")
    private let vehiclePrefix = OBALoc("search_interactor.quick_search.vehicle_prefix", value: "Vehicle:", comment: "Quick search prefix for Vehicle.")
    private let sectionHeader = OBALoc("search_controller.quick_search.header", value: "Quick Search", comment: "Quick Search section header in search")

    private var quickSearchOptions: [(SearchType, String, String)] {
        var options: [(SearchType, String, String)] = [
            (.route, routePrefix, "route"),
            (.address, addressPrefix, "place"),
            (.stopNumber, stopPrefix, "stop")
        ]

        if isVehicleSearchAvailable {
            options.append((.vehicleID, vehiclePrefix, "busTransport"))
        }

        return options
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text(sectionHeader)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Quick search options
            LazyVStack(spacing: 0) {
                ForEach(quickSearchOptions, id: \.0) { searchType, prefix, iconName in
                    QuickSearchRowView(
                        prefix: prefix,
                        searchText: searchText,
                        iconName: iconName,
                        brandColor: brandColor
                    ) {
                        onSearchTypeSelected(searchType, searchText)
                    }
                    Divider().padding(.leading, 56)
                }
            }
        }
    }
}

/// A single row in the quick search section
struct QuickSearchRowView: View {
    let prefix: String
    let searchText: String
    let iconName: String
    let brandColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon badge (colored background with white icon)
                iconBadge

                // Label with prefix and bold search text
                (Text(prefix + " ").foregroundColor(.primary) +
                 Text(searchText).bold().foregroundColor(.primary))
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var iconBadge: some View {
        Image(iconName, bundle: Bundle(for: Icons.self))
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundColor(.white)
            .frame(width: 16, height: 16)
            .frame(width: 32, height: 32)
            .background(brandColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
