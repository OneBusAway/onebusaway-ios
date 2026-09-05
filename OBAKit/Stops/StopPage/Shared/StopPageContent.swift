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

    /// The departures that survive the route filter, before the Departure Type
    /// filter and terminal dedup are applied. Kept separate from `departures` so
    /// the empty state can tell whether the route filter or the Departure Type
    /// filter emptied the page.
    let routeVisibleDepartures: [ArrivalDeparture]

    /// Departures both list modes project: hidden routes removed (when the
    /// filter is on), then the Departure Type filter, then terminal duplicates
    /// collapsed.
    let departures: [ArrivalDeparture]
    let departureIDs: Set<String>
    let routeIDs: Set<RouteID>

    let isGrouped: Bool
    let routeGroups: [StopPageListBuilder.RouteGroup<ArrivalDeparture>]
    let listIsEmpty: Bool

    let hasLoadedArrivals: Bool
    let showsLoadingState: Bool

    /// The server has no stop at this ID. A terminal state: it suppresses the
    /// loading row, which would otherwise spin forever because a missing stop
    /// never produces arrivals (#1336).
    let stopIsMissing: Bool
    /// `true` only when the route filter is what emptied the list.
    let isFilteredEmpty: Bool
    /// `true` only when the Departure Type filter is what emptied the list:
    /// rows survived the route filter and then the type filter removed them all.
    let isDepartureFilterEmpty: Bool
    let attributionText: String

    /// `true` only when this page has no stop header rendered above the content.
    ///
    /// When a stop is passed in at init (the ordinary path when a rider taps a
    /// stop), a header renders even if the first arrivals fetch fails. This means
    /// the page has content above the empty/error row, so the row should not claim
    /// most of the list's height or centre itself. It is deliberately keyed on the
    /// stop, not on the error, to avoid a regression: if a fetch then fails, the
    /// empty row must not inflate.
    let fillsPage: Bool

    init(
        stop: Stop?,
        allDepartures: [ArrivalDeparture],
        hasLoadedArrivals: Bool,
        preferences: StopPreferences,
        isListFiltered: Bool,
        arrivalDepartureFilter: ArrivalDepartureFilter,
        isLoading: Bool,
        hasError: Bool,
        isBrokenBookmark: Bool,
        stopIsMissing: Bool = false
    ) {
        let visible = isListFiltered ? allDepartures.filter(preferences: preferences) : allDepartures
        // Terminal dedup deliberately runs downstream, after the Departure Type
        // filter: dedup prefers the predicted half of an arrival/departure pair,
        // so filtering afterward could drop a scheduled row whose predicted twin
        // had already been consumed (same ordering as `StopViewController`).
        let routeVisible = visible.filteringImplausibleDates()
        // `filteringTerminalDuplicates()` collapses the arrival/departure pair
        // the API emits for a single vehicle visit at a terminal or loop stop —
        // without it the rider sees the same bus twice, with two different
        // countdowns (parity with `StopViewController`).
        let departures = routeVisible
            .filter(by: arrivalDepartureFilter)
            .filteringTerminalDuplicates()

        self.routeVisibleDepartures = routeVisible
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
        self.stopIsMissing = stopIsMissing
        // Any in-flight fetch, plus the pre-`.task` first frame (nothing
        // fetched, no error yet) so the page never flashes "No departures"
        // before the first request has even started. A missing stop is excluded
        // for the opposite reason: it has finished, and it will never have
        // arrivals, so without it the page spins forever.
        self.showsLoadingState = isLoading
            || (!hasLoadedArrivals && !hasError && !isBrokenBookmark && !stopIsMissing)

        // The stop has departures but none survive the route preferences.
        // Grouped mode can be empty while `allDepartures` isn't (every departure
        // is in the past); that's a no-service state, not a filtered-out one —
        // hence `routeVisible`, not `listIsEmpty`.
        self.isFilteredEmpty = isListFiltered && routeVisible.isEmpty && !allDepartures.isEmpty
        self.isDepartureFilterEmpty = arrivalDepartureFilter != .all
            && departures.isEmpty
            && !routeVisible.isEmpty

        self.fillsPage = stop == nil
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
            arrivalDepartureFilter: viewModel.arrivalDepartureFilter,
            isLoading: viewModel.isLoading,
            hasError: viewModel.operationError != nil,
            isBrokenBookmark: viewModel.isBrokenBookmark,
            stopIsMissing: viewModel.stopIsMissing
        )
    }
}
