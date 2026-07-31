//
//  StopPageContent.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Everything the Stop page's list needs, derived once from the view model's
/// current state.
///
/// A plain value, constructed inside a `body`, so the "one shallow body
/// re-evaluates on the view model's refresh and status-timer churn" property
/// the page is built around still holds. Being pure, it is also directly
/// testable — this logic used to be inlined in `StopPageView.body`, where it
/// wasn't.
struct StopPageContent {

    /// Departures both list modes project: hidden routes removed (when the
    /// filter is on), then terminal duplicates collapsed.
    let departures: [ArrivalDeparture]
    let departureIDs: Set<String>
    let routeIDs: Set<RouteID>

    let isGrouped: Bool
    let routeGroups: [StopPageListBuilder.RouteGroup<ArrivalDeparture>]
    let listIsEmpty: Bool

    let hasLoadedArrivals: Bool
    let showsLoadingState: Bool
    /// `true` only when the route filter is what emptied the list.
    let isFilteredEmpty: Bool
    let attributionText: String

    init(
        stop: Stop?,
        allDepartures: [ArrivalDeparture],
        hasLoadedArrivals: Bool,
        preferences: StopPreferences,
        isListFiltered: Bool,
        isLoading: Bool,
        hasError: Bool,
        isBrokenBookmark: Bool
    ) {
        // `filteringTerminalDuplicates()` collapses the arrival/departure pair
        // the API emits for a single vehicle visit at a terminal or loop stop —
        // without it the rider sees the same bus twice, with two different
        // countdowns (parity with `StopViewController`).
        let visible = isListFiltered ? allDepartures.filter(preferences: preferences) : allDepartures
        let departures = visible.filteringTerminalDuplicates()

        self.departures = departures
        self.departureIDs = Set(departures.map(\.id))
        self.routeIDs = Set(departures.map(\.routeID))

        let isGrouped = preferences.sortType == .route
        let routeGroups = isGrouped ? StopPageListBuilder.routeGroups(departures) : []
        self.isGrouped = isGrouped
        self.routeGroups = routeGroups

        // Grouped mode drops past departures, so it can have nothing to render
        // while `departures` is non-empty (the last bus of the evening has
        // left). Deciding emptiness from the groups themselves keeps that case
        // on the empty state instead of a void.
        self.listIsEmpty = isGrouped ? routeGroups.isEmpty : departures.isEmpty

        self.hasLoadedArrivals = hasLoadedArrivals
        // Any in-flight fetch, plus the pre-`.task` first frame (nothing
        // fetched, no error yet) so the page never flashes "No departures"
        // before the first request has even started.
        self.showsLoadingState = isLoading || (!hasLoadedArrivals && !hasError && !isBrokenBookmark)

        // Grouped mode can be empty while `allDepartures` isn't (every
        // departure is in the past); that's a no-service state, not a
        // filtered-out one — hence `departures`, not `listIsEmpty`.
        self.isFilteredEmpty = isListFiltered && departures.isEmpty && !allDepartures.isEmpty

        self.attributionText = Self.attribution(for: stop)
    }

    private static func attribution(for stop: Stop?) -> String {
        guard let stop else { return "" }
        let agencies = Formatters.formattedAgenciesForRoutes(stop.routes)
        guard !agencies.isEmpty else { return "" }
        let fmt = OBALoc(
            "stop_controller.data_attribution_format",
            value: "Data provided by %@",
            comment: "A string listing the data providers (agencies) for this stop's data. It contains one or more providers separated by commas. e.g. Data provided by King County Metro, Sound Transit"
        )
        return String(format: fmt, agencies)
    }
}

extension StopPageContent {
    /// Convenience for the view layer, which holds the view model.
    @MainActor
    init(viewModel: StopViewModel) {
        self.init(
            stop: viewModel.stop,
            allDepartures: viewModel.stopArrivals?.arrivalsAndDepartures ?? [],
            hasLoadedArrivals: viewModel.stopArrivals != nil,
            preferences: viewModel.stopPreferences,
            isListFiltered: viewModel.isListFiltered,
            isLoading: viewModel.isLoading,
            hasError: viewModel.operationError != nil,
            isBrokenBookmark: viewModel.isBrokenBookmark
        )
    }
}
