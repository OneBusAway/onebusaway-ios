//
//  HomeExplore.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// A shortcut in the home sheet's Explore row: something the lists above don't
/// hold, and which otherwise sits a menu or two away.
enum HomeExploreItem: Hashable, Identifiable {
    case planTrip
    /// The map's bike and scooter layers, which the tile switches on and off.
    case rentals(isOn: Bool)

    /// The items to show, in order. Each only where it leads somewhere.
    ///
    /// - Parameter rentalsEnabled: Whether the bike and scooter layers are on,
    ///   or `nil` in a region with none.
    static func items(offersTripPlanning: Bool, rentalsEnabled: Bool?) -> [HomeExploreItem] {
        var items: [HomeExploreItem] = []
        if offersTripPlanning { items.append(.planTrip) }
        if let rentalsEnabled { items.append(.rentals(isOn: rentalsEnabled)) }
        return items
    }

    /// The kind of item, not its state: a tile whose layer came on is the same tile.
    var id: String {
        switch self {
        case .planTrip: "planTrip"
        case .rentals: "rentals"
        }
    }

    var title: String {
        switch self {
        case .planTrip:
            OBALoc("home_sheet.explore.plan_trip", value: "Plan a Trip", comment: "Title of a shortcut on the map panel's home sheet that opens the trip planner. Short: it sits under a small round icon.")
        case .rentals:
            OBALoc("home_sheet.explore.rentals", value: "Bikes & Scooters", comment: "Title of a shortcut on the map panel's home sheet that shows or hides rental bikes and scooters on the map. Short: it sits under a small round icon.")
        }
    }

    var systemImage: String {
        switch self {
        case .planTrip: "point.topleft.down.to.point.bottomright.curvepath"
        case .rentals: "bicycle"
        }
    }

    /// What VoiceOver adds to the title: the state a sighted rider reads off the
    /// tile's fill.
    var accessibilityValue: String? {
        switch self {
        case .planTrip: nil
        case .rentals(let isOn): isOn ? Strings.mapLayersStateOn : Strings.mapLayersStateOff
        }
    }

    /// Whether the tile draws filled, as a control that is on.
    var isOn: Bool {
        if case .rentals(true) = self { true } else { false }
    }
}

/// The home sheet's Explore row: a line of round shortcuts, as Apple Maps has
/// for its places, with wider tiles at accessibility text sizes.
struct HomeExploreRow: View {
    let items: [HomeExploreItem]
    let onSelect: (HomeExploreItem) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Fixed columns rather than a scrolling row: a shortcut hidden off the
        // edge is one nobody finds. Three keeps the two tiles Apple Maps-sized;
        // two gives them room at accessibility sizes.
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 8, alignment: .top),
            count: typeSize.isAccessibilitySize ? 2 : 3
        )
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                HomeExploreTile(item: item) { onSelect(item) }
            }
        }
    }
}

private struct HomeExploreTile: View {
    let item: HomeExploreItem
    let action: () -> Void

    @ScaledMetric(relativeTo: .caption) private var diameter: CGFloat = 52

    /// The darker brand green: white on it, and it on the tile's grey, both
    /// clear 3:1 in either appearance, which the lighter green does not.
    private let brand = Color(uiColor: ThemeColors.shared.brandAccent)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: item.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(item.isOn ? Color.white : brand)
                    .frame(width: diameter, height: diameter)
                    .background(
                        item.isOn ? AnyShapeStyle(brand) : AnyShapeStyle(Color(.tertiarySystemFill)),
                        in: Circle()
                    )
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .label))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.accessibilityValue ?? "")
        .accessibilityAddTraits(traits)
    }

    /// The layers tile is a switch; the others go somewhere.
    private var traits: AccessibilityTraits {
        if case .rentals = item { return [.isButton, .isToggle] }
        return .isButton
    }
}

#if DEBUG
#Preview {
    HomeExploreRow(items: [.planTrip, .rentals(isOn: true)]) { _ in }
        .padding()
}
#endif
