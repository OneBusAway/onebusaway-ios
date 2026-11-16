//
//  StopDirectionsPill.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import OTPKit
import SwiftUI

/// The stop page's walk and bike times — the header's pills and the departures
/// list's walk divider — and what tapping one does. Both surfaces share this one
/// behavior, so the same tap never asks two different things.
///
/// Where the region has a trip planner, a tap offers a sheet led by directions in
/// the app ("Show Walking Directions"), with this stop as the destination and the
/// mode preselected; the walk sheet adds "Open in Maps". Without a planner, a walk
/// tap opens walking directions in a maps app, and a bike time is a plain value:
/// no maps app takes a cycling deep link.
enum StopDirectionsPill {
    case walk
    case bike

    enum Behavior: Equatable {
        /// A sheet that leads with directions in the app's trip planner, in this
        /// mode, then (walking only) the maps-app hand-off.
        case offerDirections(StopDirectionsPill)
        case openMapsWalkingDirections

        var accessibilityHint: String {
            switch self {
            case .offerDirections(.bike):
                OBALoc("stop_page.directions.bike_a11y_hint", value: "Offers bike directions to this stop.", comment: "VoiceOver hint on the stop page's bike-time buttons (header pill and departures divider) when the region has a trip planner.")
            case .offerDirections(.walk):
                OBALoc("stop_page.directions.walk_a11y_hint", value: "Offers walking directions to this stop.", comment: "VoiceOver hint on the stop page's walk-time buttons (header pill and departures divider) when the region has a trip planner.")
            case .openMapsWalkingDirections:
                OBALoc("stop_page.header.walk_a11y_hint", value: "Opens walking directions to this stop.", comment: "VoiceOver hint on the header card's walk-time button.")
            }
        }
    }

    var mode: TransportMode {
        switch self {
        case .walk: .walk
        case .bike: .bike
        }
    }

    var systemImage: String {
        switch self {
        case .walk: "figure.walk"
        case .bike: "bicycle"
        }
    }

    /// "12 min walk" / "12 min bike". Both headers show the same words in different chrome.
    func text(for info: WalkTimeInfo) -> String {
        text(minutes: info.walkMinutes)
    }

    /// "12 min walk" / "12 min bike", for callers holding just the minutes (the walk divider).
    func text(minutes: Int) -> String {
        let fmt = switch self {
        case .walk:
            OBALoc("stop_page.walk_chip_minutes_fmt", value: "%d min walk", comment: "Walk chip on the header card. %d is the walk time in minutes.")
        case .bike:
            OBALoc("stop_page.bike_chip_minutes_fmt", value: "%d min bike", comment: "Bike chip on the header card. %d is the bike time in minutes.")
        }
        return String(format: fmt, minutes)
    }

    /// "12 min": the stop sheet header's pill, whose icon says walk or bike
    /// (#1754). VoiceOver still reads `text(for:)`, which names the mode.
    func shortText(for info: WalkTimeInfo) -> String {
        String(
            format: OBALoc("stop_header.travel_minutes_fmt", value: "%d min", comment: "Visible text of the walk and bike pills in the stop sheet header; the icon says which. %d is the time in minutes."),
            info.walkMinutes
        )
    }

    /// `nil` when a tap does nothing, so the pill isn't a button.
    func behavior(tripPlannerAvailable: Bool) -> Behavior? {
        if tripPlannerAvailable { return .offerDirections(self) }
        return hasMapsHandoff ? .openMapsWalkingDirections : nil
    }

    /// Whether a maps app can take directions in this mode. No maps app takes a
    /// cycling deep link, so only walking hands off.
    var hasMapsHandoff: Bool { self == .walk }

    /// The directions sheet's title: "Walk to this stop" / "Bike to this stop".
    var offerTitle: String {
        switch self {
        case .walk:
            OBALoc("stop_page.directions.walk_sheet_title", value: "Walk to this stop", comment: "Title of the sheet shown when the rider taps a walk time on the stop page.")
        case .bike:
            OBALoc("stop_page.directions.bike_sheet_title", value: "Bike to this stop", comment: "Title of the sheet shown when the rider taps a bike time on the stop page.")
        }
    }

    /// The directions sheet's first action, which opens the app's trip planner in this mode.
    var showDirectionsTitle: String {
        switch self {
        case .walk:
            OBALoc("stop_page.directions.show_walking_directions", value: "Show Walking Directions", comment: "Action that plans a walk to this stop in the app's trip planner.")
        case .bike:
            OBALoc("stop_page.directions.show_bike_directions", value: "Show Bike Directions", comment: "Action that plans a bike trip to this stop in the app's trip planner.")
        }
    }

    static var openInMapsTitle: String {
        OBALoc("stop_page.directions.open_in_maps", value: "Open in Maps", comment: "Action that hands walking directions to this stop to a maps app.")
    }
}

/// What the stop page's walk and bike times do, as one value so the gate and the
/// action can't disagree. Shared by the header pills and the walk divider.
struct StopPillDirections {
    /// Whether the region's trip planner can open from here.
    let tripPlannerAvailable: Bool
    let perform: (StopDirectionsPill.Behavior) -> Void

    /// Plain values, for previews and placeholders.
    static let none = StopPillDirections(tripPlannerAvailable: false, perform: { _ in })
}

extension View {
    /// Makes a walk or bike time — a header pill or the departures list's walk
    /// divider — do what `pill` does on a tap, or leaves it a plain value when that
    /// is nothing. Apply after the view names its accessibility element.
    ///
    /// A tap gesture rather than a `Button`: the pills sit in a `FlowLayout`, which a
    /// `Button` answers with a greedy height (see `StopPageHeaderView`).
    @ViewBuilder
    func directionsAction(_ pill: StopDirectionsPill, _ directions: StopPillDirections) -> some View {
        if let behavior = pill.behavior(tripPlannerAvailable: directions.tripPlannerAvailable) {
            self
                .onTapGesture { directions.perform(behavior) }
                // `.onTapGesture` is invisible to assistive tech: the default action
                // is what makes the "button" trait activatable.
                .accessibilityAction { directions.perform(behavior) }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(behavior.accessibilityHint)
        } else {
            self
        }
    }
}
