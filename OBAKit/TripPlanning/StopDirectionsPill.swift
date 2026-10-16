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

/// The stop header's walk-time and bike-time pills, and what tapping one does.
///
/// Where the region has a trip planner, both ask first, then open it with this stop
/// as the destination and the pill's mode preselected. Without one, the walk pill
/// opens walking directions in a maps app, and the bike pill is a plain value: no
/// maps app takes a cycling deep link.
enum StopDirectionsPill {
    case walk
    case bike

    enum Behavior: Equatable {
        /// Confirm with `promptTitle`, then open the trip planner in this mode.
        case askThenPlanTrip(TransportMode)
        case openMapsWalkingDirections

        var accessibilityHint: String {
            switch self {
            case .askThenPlanTrip(.bike):
                OBALoc("stop_page.header.bike_trip_planner_a11y_hint", value: "Plans a bike trip to this stop in the app.", comment: "VoiceOver hint on the stop header's bike-time button when the region has a trip planner.")
            case .askThenPlanTrip:
                OBALoc("stop_page.header.walk_trip_planner_a11y_hint", value: "Plans a walk to this stop in the app.", comment: "VoiceOver hint on the stop header's walk-time button when the region has a trip planner.")
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

    /// `nil` when a tap does nothing, so the pill isn't a button.
    func behavior(tripPlannerAvailable: Bool) -> Behavior? {
        if tripPlannerAvailable { return .askThenPlanTrip(mode) }
        return self == .walk ? .openMapsWalkingDirections : nil
    }

    static var promptTitle: String {
        OBALoc("stop_page.directions_prompt.title", value: "Get directions to this stop in the app?", comment: "Title of the prompt shown when the rider taps the stop header's walk or bike time and the region has a trip planner.")
    }
}

/// What the stop header's walk and bike pills do, as one value so the gate and the
/// action can't disagree.
struct StopPillDirections {
    /// Whether the region's trip planner can open from here.
    let tripPlannerAvailable: Bool
    let perform: (StopDirectionsPill.Behavior) -> Void

    /// Plain values, for previews and placeholders.
    static let none = StopPillDirections(tripPlannerAvailable: false, perform: { _ in })
}

extension View {
    /// Makes a header pill do what `pill` does on a tap, or leaves it a plain value
    /// when that is nothing. Apply after the pill names its accessibility element.
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
