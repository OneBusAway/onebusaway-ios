//
//  StopPageView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import ActivityKit
import OBAKitCore

/// Everything that navigates away from — or presents a modal over — the Stop
/// page, implemented by the hosting `StopPageViewController` so the SwiftUI layer
/// stays router-free and holds no `Application` reference of its own.
struct StopPageNavigationHandler {
    /// Pushes the full trip screen for a departure (row context menu, trip panel).
    let showTrip: (ArrivalDeparture) -> Void
    /// Presents the whole-stop schedule (nav-bar Schedules button).
    let showScheduleForStop: () -> Void
    /// Presents the schedule for a specific departure's route (row swipe/menu and
    /// trip panel). Mirrors the legacy row `Schedule` action, which is
    /// route-scoped rather than stop-scoped.
    let showScheduleForRoute: (ArrivalDeparture) -> Void
    /// Region gate for the route-schedule affordances
    /// (`Region.supportsScheduleForRoute`); hides them where unsupported.
    let canScheduleForRoute: Bool
    /// Opens walking directions to the stop in an external maps app (header
    /// walk pill). Presents a choice sheet when more than one app is available.
    let showWalkingDirections: () -> Void
    /// Pushes the alert-detail screen for a tapped service alert.
    let showAlertDetail: (ServiceAlert) -> Void
    /// Opens the bookmark editor: `nil` for a stop-level bookmark, an
    /// `ArrivalDeparture` for a trip-level bookmark (row swipe/menu).
    let showBookmarkEditor: (ArrivalDeparture?) -> Void
    /// Starts the trip-sharing flow for a departure (row context menu):
    /// destination stop picker, then the system share sheet.
    let shareTrip: (ArrivalDeparture) -> Void
    /// Presents the alarm lead-time picker bulletin for a departure (the trip
    /// panel's Set-an-alarm button), reusing `AlarmBuilder` from the legacy
    /// stop screen.
    let showAlarmPicker: (ArrivalDeparture) -> Void
    /// Starts a Live Activity for a departure (the trip panel's Track button).
    let startLiveActivity: (ArrivalDeparture) -> Void
    /// Shows the "couldn't open survey" alert when an external survey link fails.
    let showExternalSurveyError: () -> Void
    /// Presents the donation learn-more/donate modal.
    let showDonation: () -> Void
    /// Presents the donation dismiss action sheet; invokes the completion when the
    /// user actually hides the card (dismiss or remind-later, not cancel).
    let dismissDonation: (@escaping () -> Void) -> Void
    /// Lazily builds the row long-press trip preview as an `AnyView`.
    let makeTripPreview: (ArrivalDeparture) -> AnyView

    // The four below exist only for the sheet presentation's bottom toolbar. The pushed
    // presentation reaches the same flows through `configureBarButtons()`' UIKit menus, which
    // call the hosting VC's methods directly.

    /// Presents the route-filter picker (`StopPreferencesWrappedView`).
    let showRouteFilter: () -> Void
    /// Pushes the service-alert list for this stop.
    let showServiceAlerts: () -> Void
    /// Pushes the nearby-stops list.
    let showNearbyStops: () -> Void
    /// Presents the report-a-problem flow.
    let showReportProblem: () -> Void
    /// Dismisses the sheet (its header's close button). No-op in the pushed presentation, which
    /// leaves instead through the navigation bar's back button.
    let closeSheet: () -> Void
}

/// Thin hosting wrapper for `StopPageView`. Its only job is to apply
/// `.defaultAppStorage` so the page's `@AppStorage` reads and writes the
/// app-group suite (matching the legacy screen + view model) rather than
/// `UserDefaults.standard`. It deliberately does NOT observe `StopViewModel` —
/// `StopPageView` remains the sole observer.
struct StopPageRootView: View {
    let viewModel: StopViewModel
    let userDefaults: UserDefaults
    let snapshotLoader: (CGSize) async -> UIImage?
    let navigation: StopPageNavigationHandler
    /// The app's shared `Formatters`, injected so the departure views format
    /// times through the same instance as the rest of the app instead of
    /// spinning up ad-hoc `DateFormatter`s.
    let formatters: Formatters
    /// The map's focus channel. A plain pass-through here (see `StopPageView`'s note on
    /// observation discipline) — only `StopPageSheetHeaderView` observes it.
    let mapFocus: StopMapFocus
    /// `true` when the page is presented as a sheet over the map: the header goes light and
    /// compact, and the chrome moves from the navigation bar to a bottom toolbar. `false` — the
    /// pushed presentation — leaves both exactly as they were.
    var showToolbarOnBottom = false
    /// `true` while the sheet sits at its `.tip` detent, where there is room for one row of
    /// chrome and nothing else: the bottom toolbar goes away and the header collapses to the
    /// stop name and its close button.
    var isCollapsed = false

    var body: some View {
        StopPageView(
            viewModel: viewModel,
            userDefaults: userDefaults,
            snapshotLoader: snapshotLoader,
            navigation: navigation,
            mapFocus: mapFocus,
            showToolbarOnBottom: showToolbarOnBottom,
            isCollapsed: isCollapsed
        )
        .defaultAppStorage(userDefaults)
        .environment(\.obaFormatters, formatters)
    }
}

/// Root view of the redesigned Stop page. This is the ONLY view that observes
/// `StopViewModel`; every subview receives plain values so the VM's frequent
/// `@Published` churn (refresh + status timers) re-evaluates one shallow body.
struct StopPageView: View {
    @ObservedObject var viewModel: StopViewModel

    /// The app-group suite (injected from the hosting VC). Used for the
    /// "last used sort" seed/write so the SwiftUI page shares the same store as
    /// the legacy screen; `@AppStorage` picks up the same suite via
    /// `.defaultAppStorage` applied by `StopPageRootView`.
    let userDefaults: UserDefaults

    /// Produces the header map snapshot at a concrete size. Supplied by the
    /// hosting VC so this view stays UIKit-free.
    let snapshotLoader: (CGSize) async -> UIImage?

    /// Everything that leaves the page or presents a VC-owned modal. Supplied by
    /// the hosting VC so this view stays router-free.
    let navigation: StopPageNavigationHandler

    /// The map's focus channel. A plain pass-through — `StopPageSheetHeaderView` is the one view
    /// in this subtree that observes it. Observing it here too would re-evaluate this view's
    /// entire departures list on every refresh and every chip tap, on top of the VM churn this
    /// view already re-evaluates for (see the type doc comment above).
    let mapFocus: StopMapFocus

    /// Selects the sheet presentation's chrome: the light `StopPageSheetHeaderView` and a bottom
    /// `StopPageToolbar`. `false` keeps the pushed presentation's dark map header and leaves the
    /// chrome in the navigation bar, where `configureBarButtons()` puts it.
    var showToolbarOnBottom = false
    /// `true` while the sheet is at its `.tip` detent. Decoupled from `showToolbarOnBottom` so
    /// the chrome can shrink to fit the detent without changing which presentation is in play.
    var isCollapsed = false

    /// The bottom toolbar has no room at `.tip`, where the sheet is barely onscreen.
    private var showBottomToolbar: Bool {
        showToolbarOnBottom && !isCollapsed
    }

    @State private var expandedRouteID: RouteID?
    @State private var didSeedMode = false
    /// Set when the user explicitly dismisses the donation card, so it disappears
    /// immediately instead of waiting for the next view-model refresh to re-read
    /// `shouldRequestDonations`.
    @State private var donationHidden = false
    @AppStorage("StopViewController.pastDeparturesCollapsed") private var pastCollapsed = true

    /// Global (not per-stop) "last mode the user picked" seed. A stop the user
    /// has never customized opens in this mode; touched in exactly two places —
    /// read in `seedLastUsedModeIfNeeded()`, written in the toggle's `onChange`.
    private static let lastUsedStopSortKey = "OBALastUsedStopSort"

    /// Leading/trailing inset shared by the page's full-width card rows
    /// (header, survey, donation), matching the inset-grouped card margin.
    private static let horizontalRowInset: CGFloat = 0

    /// `true` once any fetch has succeeded (errors don't clear `stopArrivals`).
    /// Gates the chrome that means nothing before data exists — the mode
    /// toggle, the donation card, and the Load-more/attribution footer — so
    /// the first load reads as one deliberate loading page rather than empty
    /// controls scattered around a spinner.
    private var hasLoadedArrivals: Bool {
        viewModel.stopArrivals != nil
    }

    /// `true` when the empty departures area should show the loading treatment
    /// rather than an empty state: any in-flight fetch, plus the pre-`.task`
    /// first frame (nothing fetched, no error yet) so the page never flashes
    /// "No departures" before the first request has even started.
    private var showsLoadingState: Bool {
        viewModel.isLoading || (!hasLoadedArrivals && viewModel.operationError == nil && !viewModel.isBrokenBookmark)
    }

    /// The departures that survive the route filter, before the Departure Type
    /// filter and terminal dedup are applied. Kept separate from the fully
    /// filtered list so the empty state can tell whether the route filter or
    /// the Departure Type filter emptied the page.
    private var routeVisibleDepartures: [ArrivalDeparture] {
        let all = viewModel.stopArrivals?.arrivalsAndDepartures ?? []
        let visible = viewModel.isListFiltered ? all.filter(preferences: viewModel.stopPreferences) : all
        // Terminal dedup deliberately runs downstream, after the Departure Type
        // filter — see the ordering note at the `departures` binding below.
        return visible.filteringImplausibleDates()
    }

    private var attributionText: String {
        guard let stop = viewModel.stop else { return "" }
        let agencies = Formatters.formattedAgenciesForRoutes(stop.routes)
        guard !agencies.isEmpty else { return "" }
        let fmt = OBALoc(
            "stop_controller.data_attribution_format",
            value: "Data provided by %@",
            comment: "A string listing the data providers (agencies) for this stop's data. It contains one or more providers separated by commas. e.g. Data provided by King County Metro, Sound Transit"
        )
        return String(format: fmt, agencies)
    }

    var body: some View {
        // Hoist the single computed walk value so the header chip, the
        // chronological partition, and the divider all read one snapshot of it.
        let walkTime = viewModel.walkTime
        // Route filter, then Departure Type filter, then terminal dedup — the
        // type filter must run before `filteringTerminalDuplicates()`: dedup
        // prefers the predicted half of an arrival/departure pair, so filtering
        // afterward could drop a scheduled row whose predicted twin had already
        // been consumed (same ordering as `StopViewController`).
        let routeVisible = routeVisibleDepartures
        let departures = routeVisible
            .filter(by: viewModel.arrivalDepartureFilter)
            .filteringTerminalDuplicates()
        let departureIDs = Set(departures.map(\.id))
        let routeIDs = Set(departures.map(\.routeID))
        // Grouped mode drops past departures, so it can have nothing to render
        // while `departures` is non-empty (the last bus of the evening has left).
        // Deciding emptiness from the groups themselves — rather than from
        // `departures` — keeps that case on the empty state instead of a void.
        let isGrouped = viewModel.stopPreferences.sortType == .route
        let routeGroups = isGrouped ? StopPageListBuilder.routeGroups(departures) : []
        let listIsEmpty = isGrouped ? routeGroups.isEmpty : departures.isEmpty
        // Hoisted for the same reason as `walkTime`: the header row's Past count and
        // the list's past section have to be reading the same partition.
        let chronologicalPartition = StopPageListBuilder.chronologicalPartition(
            departures,
            walkMinutes: walkTime?.walkMinutes
        )

        List {
            if let stop = viewModel.stop {
                if !showToolbarOnBottom {
                    Section {
                        StopPageHeaderView(stop: stop, walkTime: walkTime, statusText: viewModel.statusText, snapshotLoader: snapshotLoader, onWalkingDirections: navigation.showWalkingDirections)
                            .listRowInsets(EdgeInsets(top: 0, leading: Self.horizontalRowInset, bottom: 0, trailing: Self.horizontalRowInset))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            } else if showsLoadingState {
                // Loading only. A first fetch that fails leaves no header at
                // all — a "loading" skeleton sitting above an error message
                // reads as two contradictory states on one page; the centered
                // error row below owns the screen instead.
                if !showToolbarOnBottom {
                    Section {
                        StopPageHeaderPlaceholderView()
                            .listRowInsets(EdgeInsets(top: 0, leading: Self.horizontalRowInset, bottom: 0, trailing: Self.horizontalRowInset))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }

            if let survey = viewModel.currentSurvey {
                Section {
                    SurveyCardRepresentable(
                        survey: survey,
                        stopID: viewModel.stopID,
                        onNext: { answer in
                            Task { await viewModel.submitHeroAnswer(answer, stopLocation: viewModel.stop?.coordinate) }
                        },
                        onDismiss: { viewModel.dismissCurrentSurvey() },
                        onOpenExternalSurvey: {
                            viewModel.launchExternalSurvey(survey, onFailure: navigation.showExternalSurveyError)
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: Self.horizontalRowInset, bottom: 4, trailing: Self.horizontalRowInset))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            // Inline donation request (parity with the legacy UIKit `DonationListItem`).
            // Gated on the view model's `shouldRequestDonations`; all three actions
            // present VC-owned modals via the navigation handler. Sits after the
            // survey and before service alerts, matching the legacy section order.
            if hasLoadedArrivals && viewModel.shouldRequestDonations && !donationHidden {
                Section {
                    DonationCardRepresentable(
                        onDonate: navigation.showDonation,
                        onLearnMore: navigation.showDonation,
                        onClose: { navigation.dismissDonation { donationHidden = true } }
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: Self.horizontalRowInset, bottom: 4, trailing: Self.horizontalRowInset))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            if let alerts = viewModel.stopArrivals?.serviceAlerts, !alerts.isEmpty {
                ServiceAlertsSection(alerts: alerts, onSelect: navigation.showAlertDetail)
            }

            if hasLoadedArrivals {
                Section {
                    StopPageListHeaderRow(
                        mode: viewModel.stopPreferences.sortType,
                        // Grouped mode has no past partition, so it has nothing to disclose.
                        pastCount: isGrouped ? 0 : chronologicalPartition.past.count,
                        showPast: !pastCollapsed,
                        onTogglePast: { withAnimation { pastCollapsed.toggle() } },
                        onChangeMode: { newValue in
                            withAnimation {
                                // Switching modes collapses the open route card.
                                expandedRouteID = nil
                                userDefaults.set(newValue.rawValue, forKey: Self.lastUsedStopSortKey)
                                viewModel.updateSortType(newValue)
                            }
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            if listIsEmpty {
                if showsLoadingState {
                    Section {
                        StopPageLoadingRow()
                    }
                } else {
                    Section {
                        StopPageEmptyStateRow(
                            isBrokenBookmark: viewModel.isBrokenBookmark,
                            errorText: viewModel.operationErrorMessage,
                            // Only when the route filter is what emptied the list:
                            // the stop has departures but none survive the route
                            // preferences. Grouped mode can be empty while
                            // `departures` isn't (every departure is in the past);
                            // that's a no-service state, not a filtered-out one.
                            isFilteredEmpty: viewModel.isListFiltered
                                && routeVisible.isEmpty
                                && !(viewModel.stopArrivals?.arrivalsAndDepartures.isEmpty ?? true),
                            // Only when the Departure Type filter is what emptied
                            // it: rows survived the route filter and then the
                            // type filter removed every one of them.
                            isDepartureFilterEmpty: viewModel.arrivalDepartureFilter != .all
                                && departures.isEmpty
                                && !routeVisible.isEmpty,
                            minutesAfter: viewModel.minutesAfter,
                            // With no header card above it (first fetch failed
                            // before the stop resolved), the row is the whole
                            // page — center it vertically so it reads as a
                            // designed full-screen state rather than content
                            // stranded under the nav bar.
                            fillsPage: viewModel.stop == nil,
                            onRetry: { Task { await viewModel.refresh() } },
                            onShowAllRoutes: { viewModel.isListFiltered = false },
                            onShowAllDepartureTypes: { viewModel.updateArrivalDepartureFilter(.all) }
                        )
                    }
                }
            } else if !isGrouped {
                ChronologicalListView(
                    // Same value the header row counts its Past disclosure from —
                    // two derivations of the same partition could disagree about
                    // whether there is anything to disclose.
                    partition: chronologicalPartition,
                    walkMinutes: walkTime?.walkMinutes,
                    showPast: !pastCollapsed,
                    statusProvider: { DepartureStatus(arrivalDeparture: $0) },
                    alarmLookup: { viewModel.alarm(for: $0) },
                    actionsProvider: makeActions(for:),
                    onSelectDeparture: { navigation.showTrip($0) }
                )
            } else {
                GroupedListView(
                    groups: routeGroups,
                    expandedRouteID: expandedRouteID,
                    statusProvider: { DepartureStatus(arrivalDeparture: $0) },
                    alarmLookup: { viewModel.alarm(for: $0) },
                    alarmLeadTime: { viewModel.alarmLeadTimeMinutes($0) },
                    canAlarm: { viewModel.canCreateAlarm(for: $0) },
                    onToggleRoute: { routeID in
                        withAnimation(.snappy) {
                            expandedRouteID = expandedRouteID == routeID ? nil : routeID
                        }
                    },
                    onSelectDeparture: { navigation.showTrip($0) },
                    onAlarmToggle: { departure in
                        if viewModel.alarm(for: departure) != nil {
                            Task { await viewModel.cancelAlarm(for: departure) }
                        } else {
                            navigation.showAlarmPicker(departure)
                        }
                    },
                )
            }

            if hasLoadedArrivals {
                StopPageFooterSection(
                    showLoadMore: !viewModel.isLoadMoreExhausted,
                    isLoading: viewModel.isLoading,
                    attribution: attributionText,
                    onLoadMore: { Task { await viewModel.loadMoreDepartures() } }
                )
            }
        }
        // `.plain` (rather than `.insetGrouped`) so sections have no horizontal
        // card margin insetting them from the screen edges. That margin is
        // separate from `listRowInsets` (which only pads inside a row's
        // background), which is why zeroing the row insets alone left a gap.
        // With `.plain`, rows whose `listRowInsets` leading/trailing are 0 sit
        // flush with the screen edges.
        .listStyle(.plain)
        // Mirror of the bottom toolbar pattern: pins the sheet header at the safe-area
        // boundary (just below the nav bar) so its position is identical at every detent.
        // A VStack wrapper respected the raw top safe area differently at `.tip` vs `.half`
        // — the nav bar isn't fully visible at `.tip`, so safe area ≈ 0 there but ≈ 44 pt
        // at `.half`, causing the header to droop. `safeAreaInset` avoids that by delegating
        // positioning to the List's own safe-area logic, the same way `.bottom` does for the
        // toolbar. The push presentation is unaffected; it still uses its map-snapshot list row.
        .safeAreaInset(edge: .top, spacing: 0) {
            if showToolbarOnBottom {
                if let stop = viewModel.stop {
                    StopPageSheetHeaderView(stop: stop, walkTime: walkTime, onWalkingDirections: navigation.showWalkingDirections, onClose: navigation.closeSheet, isCollapsed: isCollapsed, mapFocus: mapFocus)
                } else {
                    // Unconditional, unlike the pushed presentation's header: with no navigation
                    // bar behind the sheet, this strip carries the only close button, so a stop
                    // whose first fetch failed must still render it.
                    StopPageSheetHeaderPlaceholderView(showsSkeleton: showsLoadingState, onClose: navigation.closeSheet, isCollapsed: isCollapsed)
                }
            }
        }
        // `safeAreaInset` rather than an overlay: the list needs the bar's height added to its
        // bottom inset, or the last departure sits permanently underneath it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showBottomToolbar {
                toolbar
            }
        }
        .task { await viewModel.start() }
        .onAppear(perform: seedLastUsedModeIfNeeded)
        .onDisappear { viewModel.deactivate() }
        .refreshable { await viewModel.refresh() }
        // Reconcile the open route card against the live feed: when a refresh
        // drops the expanded route from the list, clear the stale expansion.
        .onChange(of: routeIDs) { _, ids in
            if let rid = expandedRouteID, !ids.contains(rid) { expandedRouteID = nil }
        }
        .overlay(alignment: .bottom) {
            if viewModel.liveActivityStarted {
                Text(OBALoc("live_activity.started.title", value: "Tracking on Lock Screen", comment: "Toast shown when a Live Activity starts on the Lock Screen"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.tint, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: viewModel.liveActivityStarted)
    }

    /// The sheet presentation's bottom chrome. Reads the view model directly — `StopPageView` is
    /// the page's only observer, so the freshness label and filter state stay live without
    /// another subview subscribing.
    private var toolbar: some View {
        StopPageToolbar(
            statusText: viewModel.statusText,
            isRefreshing: viewModel.isLoading,
            isFilterOn: viewModel.stopPreferences.hasHiddenRoutes && viewModel.isListFiltered,
            // A single-route stop has nothing to filter down to.
            canFilter: (viewModel.stop?.routes.count ?? 0) > 1,
            isListFiltered: viewModel.isListFiltered,
            activeDepartureFilter: viewModel.arrivalDepartureFilter,
            hasServiceAlerts: !(viewModel.stopArrivals?.serviceAlerts ?? []).isEmpty,
            onRefresh: { Task { await viewModel.refresh() } },
            onSetListFiltered: { filtered in
                viewModel.isListFiltered = filtered
                // Picking "Filtered Routes" opens the picker, matching the pushed
                // presentation's `filterMenu()` — otherwise choosing it on a stop with no
                // saved hidden routes silently does nothing.
                if filtered { navigation.showRouteFilter() }
            },
            onSetDepartureFilter: { viewModel.updateArrivalDepartureFilter($0) },
            onBookmark: { navigation.showBookmarkEditor(nil) },
            onSchedule: navigation.showScheduleForStop,
            onServiceAlerts: navigation.showServiceAlerts,
            onNearbyStops: navigation.showNearbyStops,
            onWalkingDirections: navigation.showWalkingDirections,
            onReportProblem: navigation.showReportProblem
        )
    }

    /// One-shot: a stop the user has never customized opens in the last mode they
    /// picked anywhere in the app. A stop with saved preferences owns its sort
    /// type and is left alone — including one deliberately set to Chronological,
    /// which `stopPreferences.sortType` alone can't tell apart from the default.
    private func seedLastUsedModeIfNeeded() {
        guard !didSeedMode else { return }
        didSeedMode = true
        guard !viewModel.hasCustomizedPreferences,
              let raw = userDefaults.string(forKey: Self.lastUsedStopSortKey),
              let seeded = StopSort(rawValue: raw)
        else { return }
        viewModel.seedSortType(seeded)
    }

    /// Builds the shared trip-detail panel (§4.6) for an expanded departure.
    /// `StopPageView` is the only view that touches the VM, so the panel receives
    /// plain values plus closures — the `approachLoader` closure wraps the cached,
    /// live-only VM fetch; the alarm closures route through the single alarm index.
    private func makeActions(for departure: ArrivalDeparture) -> DepartureRowActions {
        DepartureRowActions(
            canAlarm: viewModel.canCreateAlarm(for: departure),
            canSchedule: navigation.canScheduleForRoute,
            hasAlarm: viewModel.alarm(for: departure) != nil,
            onAlarmToggle: {
                if viewModel.alarm(for: departure) != nil {
                    Task { await viewModel.cancelAlarm(for: departure) }
                } else {
                    navigation.showAlarmPicker(departure)
                }
            },
            onSchedule: { navigation.showScheduleForRoute(departure) },
            onBookmark: { navigation.showBookmarkEditor(departure) },
            onShowTrip: { navigation.showTrip(departure) },
            onShareTrip: { navigation.shareTrip(departure) },
            makePreview: { navigation.makeTripPreview(departure) }
        )
    }
}

#Preview("Initial loading") {
    List {
        Section {
            StopPageHeaderPlaceholderView()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        Section {
            StopPageLoadingRow()
        }
    }
    .listStyle(.plain)
}

#Preview("First-load error") {
    List {
        Section {
            StopPageEmptyStateRow(
                errorText: "Expected to receive json data from the server, but we received nothing instead.",
                isFilteredEmpty: false,
                minutesAfter: 35,
                fillsPage: true,
                onRetry: {},
                onShowAllRoutes: {}
            )
        }
    }
    .listStyle(.plain)
}

#Preview("AX5 adaptive controls") {
    ScrollView {
        VStack(spacing: 24) {
            StopPageModeToggle(mode: .time) { _ in }
            WalkLineDivider(walkMinutes: 4)
            AlarmControlView(
                alarmIsSet: true,
                leadTimeMinutes: 5,
                onSet: {}, onCancel: {}, onChange: {}
            )
        }
        .padding()
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Sheet presentation (showToolbarOnBottom)") {
    List {
        Section {
            StopPageLoadingRow()
        }
    }
    .listStyle(.plain)
    .safeAreaInset(edge: .top, spacing: 0) {
        StopPageSheetHeaderPlaceholderView(onClose: {})
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
        StopPageToolbar(
            statusText: "",
            isRefreshing: false,
            isFilterOn: false,
            canFilter: true,
            isListFiltered: false,
            activeDepartureFilter: .all,
            hasServiceAlerts: false,
            onRefresh: {}, onSetListFiltered: { _ in }, onSetDepartureFilter: { _ in },
            onBookmark: {}, onSchedule: {},
            onServiceAlerts: {}, onNearbyStops: {}, onWalkingDirections: {}, onReportProblem: {}
        )
    }
}

/// The footer: "Load more" (hidden once auto-extend hits the 12 h cap) and the
/// data-attribution line. The button is a centered glass capsule echoing the
/// mode toggle's backdrop, and swaps its plus glyph for a spinner while a
/// refresh is in flight.
struct StopPageFooterSection: View {
    let showLoadMore: Bool
    let isLoading: Bool
    let attribution: String
    let onLoadMore: () -> Void

    var body: some View {
        Section {
            if showLoadMore {
                Button(action: onLoadMore) {
                    HStack(spacing: 8) {
                        // Fixed-size slot so the glyph→spinner swap doesn't
                        // shift the text.
                        ZStack {
                            if isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "plus")
                                    .font(.footnote.weight(.bold))
                            }
                        }
                        .frame(width: 16, height: 16)
                        Text(OBALoc("stop_page.load_more", value: "Load more", comment: "Extends the departure time window"))
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(isLoading ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                    .padding(.horizontal, 24)
                    .frame(minHeight: 44)
                    .modifier(GlassContainerBackground(usesCapsule: true))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .padding(.vertical, 6)
            }
            if !attribution.isEmpty {
                Text(attribution)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }
}

/// The loading treatment for an empty departures area — the first fetch and
/// any empty-window refresh (auto-extension, Load more). A large spinner with
/// a caption, so the in-progress state reads as deliberate rather than as a
/// bare indicator floating in a blank page.
struct StopPageLoadingRow: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(OBALoc("stop_page.loading_departures", value: "Loading departures…", comment: "Caption under the spinner shown while the stop page's departure list loads."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

/// The single empty-state row shown when there are no departures to list.
/// Precedence: a bookmark pointing at a stop that no longer exists → a network
/// error (Retry) → everything filtered out (Show all routes) → genuinely no
/// service in the window. §4.4 wording is exact.
struct StopPageEmptyStateRow: View {
    /// The stop behind a bookmark no longer resolves — almost always an agency
    /// stop-ID realignment. Tells the user to recreate the bookmark rather than
    /// leaving them to conclude the bus simply isn't running (parity with
    /// `StopViewController.emptyData(for:)`).
    var isBrokenBookmark: Bool = false
    let errorText: String?
    let isFilteredEmpty: Bool
    /// The Departure Type filter (real-time only / scheduled only) removed
    /// every departure the route filter let through.
    var isDepartureFilterEmpty: Bool = false
    let minutesAfter: UInt
    /// `true` when the row is the page's only content (no header card above
    /// it): the row claims most of the list's height so its message sits
    /// centered on screen instead of stranded under the nav bar.
    var fillsPage: Bool = false
    let onRetry: () -> Void
    let onShowAllRoutes: () -> Void
    var onShowAllDepartureTypes: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true) // decorative; the message text carries the meaning
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: fillsPage ? 420 : nil)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var symbolName: String {
        if isBrokenBookmark { return "bookmark.slash.fill" }
        if errorText != nil { return "exclamationmark.icloud" }
        if isFilteredEmpty { return "line.3.horizontal.decrease.circle" }
        if isDepartureFilterEmpty { return "antenna.radiowaves.left.and.right" }
        return "clock.badge.xmark"
    }

    private var message: String {
        if isBrokenBookmark {
            return OBALoc("stop_controller.bad_bookmark_error_message", value: "This bookmark may not work anymore. Did your transit agency change something? Please delete and recreate the bookmark.", comment: "An error message displayed when a stop is shown by tapping on a bookmark—and the bookmark doesn't seem to point to a valid stop any longer. This problem will occur when a transit agency changes its stop IDs, perhaps as part of an annual transit system realignment.")
        }
        if let errorText { return errorText }
        if isFilteredEmpty {
            return OBALoc("stop_page.empty.all_filtered", value: "All routes at this stop are filtered", comment: "Empty state shown when every route at the stop is hidden by the user's filter.")
        }
        if isDepartureFilterEmpty {
            return OBALoc("stop_page.empty.departure_filter", value: "No departures match the current Departure Type filter", comment: "Empty state shown when the Departure Type filter (real-time only / scheduled only) hides every departure at the stop.")
        }
        let fmt = OBALoc("stop_page.empty.no_departures_fmt", value: "No departures in the next %d minutes", comment: "Empty state shown when the stop has no upcoming departures within the loaded time window. %d is the number of minutes. Plural forms live in Localizable.stringsdict; the value above is only the not-found fallback.")
        return String(format: fmt, minutesAfter)
    }

    private var actionTitle: String? {
        // A broken bookmark has no retry: the stop ID itself is gone, so refetching
        // it just fails again. The message tells the user to recreate the bookmark.
        if isBrokenBookmark { return nil }
        if errorText != nil {
            return OBALoc("stop_page.empty.retry", value: "Retry", comment: "Button that retries loading departures after an error.")
        }
        if isFilteredEmpty {
            return OBALoc("stop_page.empty.show_all_routes", value: "Show all routes", comment: "Button that clears the route filter so all routes are shown.")
        }
        if isDepartureFilterEmpty {
            return OBALoc("stop_page.empty.show_all_departure_types", value: "Show all departure types", comment: "Button that resets the Departure Type filter so every departure is shown.")
        }
        return nil
    }

    private func action() {
        if errorText != nil {
            onRetry()
        } else if isFilteredEmpty {
            onShowAllRoutes()
        } else if isDepartureFilterEmpty {
            onShowAllDepartureTypes()
        }
    }
}
