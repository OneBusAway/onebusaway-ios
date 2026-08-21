//
//  SearchPlaceholder.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// The search field's placeholder copy, shared by the home sheet's search bar and
/// the search sheet's field so the text doesn't change when the user taps through.
///
/// Mirrors `MapFloatingPanelController.updateSearchBarPlaceholderText()`.
enum SearchPlaceholder {

    /// Empty when no region is selected, matching the UIKit panel, which sets the
    /// search bar's placeholder to `nil` in that case.
    @MainActor
    static func text(for application: Application) -> String {
        guard let region = application.regionsService.currentRegion else { return "" }

        if application.features.tripPlanning == .running {
            return OBALoc(
                "map_floating_panel.where_are_you_going",
                value: "Where are you going?",
                comment: "Search bar placeholder on the map floating panel when the trip planner is enabled."
            )
        }

        return Formatters.searchPlaceholderText(region: region)
    }
}
