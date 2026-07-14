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

    /// Read from the environment rather than the `formatters` property `StopPageRootView`
    /// publishes: this view is constructed by that wrapper, so its own property wrappers
    /// resolve against the environment it was handed.
    @Environment(\.obaFormatters) private var formatters
    /// Gates the rotor's entry list, the one piece of per-body work here that scales with
    /// the whole departure list rather than the handful of rows the `List` materializes.
    /// An environment read, not `UIAccessibility.isVoiceOverRunning`, so switching
    /// VoiceOver on invalidates the body instead of waiting for an incidental one.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    @State private var expandedRouteID: RouteID?
    /// Set when the user explicitly dismisses the donation card, so it disappears
    /// immediately instead of waiting for the next view-model refresh to re-read
    /// `shouldRequestDonations`.
    @State private var donationHidden = false
    @AppStorage("StopViewController.pastDeparturesCollapsed") private var pastCollapsed = true

    var body: some View {
        // Hoist the mode-aware walk value so the chronological partition and the
        // divider read one snapshot of it. The header shows its own always-on
        // walk and bike estimates, independent of Bike Mode.
        let walkTime = viewModel.walkTime
        let content = StopPageContent(viewModel: viewModel)

        let rotorEntries = voiceOverEnabled
            ? departuresRotorEntries(content: content, walkMinutes: walkTime?.walkMinutes)
            : []

        List {
            if let stop = viewModel.stop {
                if !showToolbarOnBottom {
                    Section {
                        StopPageHeaderView(stop: stop, walkTime: viewModel.headerWalkTime, bikeTime: viewModel.headerBikeTime, statusText: viewModel.statusText, snapshotLoader: snapshotLoader, onWalkingDirections: navigation.showWalkingDirections)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            } else if content.showsLoadingState {
                // Loading only. A first fetch that fails leaves no header at
                // all — a "loading" skeleton sitting above an error message
                // reads as two contradictory states on one page; the centered
                // error row below owns the screen instead.
                if !showToolbarOnBottom {
                    Section {
                        StopPageHeaderPlaceholderView()
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }

            departuresBuilder.sections(content: content, walkTime: walkTime)
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
                    StopPageSheetHeaderPlaceholderView(showsSkeleton: content.showsLoadingState, onClose: navigation.closeSheet, isCollapsed: isCollapsed)
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
        .refreshable { await refreshAndAnnounce() }
        .stopPageLifecycle(
            viewModel: viewModel,
            userDefaults: userDefaults,
            liveActivityStarted: viewModel.liveActivityStarted
        )
        // Reconcile the open route card against the live feed: when a refresh
        // drops the expanded route from the list, clear the stale expansion.
        .onChange(of: content.routeIDs) { _, ids in
            if let rid = expandedRouteID, !ids.contains(rid) { expandedRouteID = nil }
        }
        // A custom rotor so a VoiceOver user can spin to "Departures" and flick
        // straight through the buses, skipping the header, status line, survey,
        // donation, service-alerts card, and the mode/Past controls above them —
        // the "so much information … hard to get bus schedules" complaint. Entries
        // bind to the rows by the same id the ForEach uses (departure id in
        // chronological mode, route id in grouped mode).
        .accessibilityRotor(Text(Self.departuresRotorTitle)) {
            ForEach(rotorEntries, id: \.id) { entry in
                AccessibilityRotorEntry(entry.label, id: entry.id)
            }
        }
        // Announce dynamic changes that otherwise mutate the list silently.
        .onChange(of: viewModel.arrivalDepartureFilter) { _, _ in
            AccessibilityNotification.Announcement(Self.filterChangedAnnouncement).post()
        }
        .onChange(of: viewModel.isListFiltered) { _, filtered in
            AccessibilityNotification.Announcement(filtered ? Self.routesFilteredAnnouncement : Self.routesAllAnnouncement).post()
        }
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
            onRefresh: { Task { await refreshAndAnnounce() } },
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

    /// The shared assembly of the departures list. Identical to the one the map
    /// sheet builds apart from `onRetry`: this presentation offers
    /// pull-to-refresh, so a retry is just a refresh.
    private var departuresBuilder: StopDeparturesBuilder {
        StopDeparturesBuilder(
            viewModel: viewModel,
            navigation: navigation,
            userDefaults: userDefaults,
            onRetry: { Task { await viewModel.refresh() } },
            expandedRouteID: $expandedRouteID,
            donationHidden: $donationHidden,
            pastCollapsed: $pastCollapsed
        )
    }

    // MARK: - VoiceOver announcements

    /// The rows the custom "Departures" rotor steps through, in the order the
    /// list renders them. Each `id` matches the row's `ForEach` identity —
    /// departure id in chronological mode, route id in grouped mode, both
    /// `String` — so the rotor lands on the real rows. Collapsed Past rows are
    /// left out; there is nothing rendered for the rotor to focus.
    ///
    /// The chronological order is read from `chronologicalPartition` rather than
    /// re-derived here. A plain time sort happens to produce the same sequence
    /// today, and costs the same one sort — but it is a second copy of "what
    /// order do departures come in, and what counts as past" with no test tying
    /// the two together, so a change to the builder would silently land the
    /// rotor on rows in an order the screen doesn't show. `ChronologicalListView`
    /// renders past (when expanded) → missed → reachable, which is what this
    /// concatenation reproduces.
    private func departuresRotorEntries(content: StopPageContent, walkMinutes: Int?) -> [(label: String, id: String)] {
        if content.isGrouped {
            return content.routeGroups.map { (rotorLabel(for: $0.next), $0.routeID) }
        }
        let partition = StopPageListBuilder.chronologicalPartition(content.departures, walkMinutes: walkMinutes)
        let rendered = (pastCollapsed ? [] : partition.past) + partition.missed + partition.reachable
        return rendered.map { (rotorLabel(for: $0), $0.id) }
    }

    /// Spoken form of a departure's route, e.g. "Route 49 - University District".
    /// The rows speak a whole sentence (route, timing, status); the rotor only has
    /// to say which bus it just landed on, but it says it the way the rest of the
    /// app does rather than reading the on-screen string and its em dash aloud.
    private func rotorLabel(for departure: ArrivalDeparture) -> String {
        formatters.accessibilityLabel(for: departure)
    }

    /// Pull-to-refresh and the toolbar's Refresh button — the two places the rider
    /// asks for fresh times and so has reason to be told they arrived. Deliberately
    /// not the 15-second auto-refresh, which runs through the same view model call
    /// and would interrupt whatever VoiceOver is reading four times a minute.
    ///
    /// Keyed on `lastUpdated` moving rather than on the call returning, because
    /// `refresh()` returns without fetching in two cases that must stay silent: a
    /// refresh already in flight (the auto-refresh timer) makes it a no-op, and a
    /// failed fetch lands in `operationError` and leaves the old times on screen.
    /// Announcing either as "Departures updated" tells a rider who can't see the
    /// stale rows that they're fresh.
    private func refreshAndAnnounce() async {
        let updatedBefore = viewModel.lastUpdated
        await viewModel.refresh()
        guard viewModel.lastUpdated != updatedBefore else { return }
        AccessibilityNotification.Announcement(Self.refreshedAnnouncement).post()
    }

    /// The rotor's title and the list's heading name the same thing, so they share
    /// one string — two keys would let 13 locales translate them apart.
    private static let departuresRotorTitle = StopPageListHeaderRow.departuresHeading
    private static let refreshedAnnouncement = OBALoc("stop_page.a11y.refreshed", value: "Departures updated", comment: "VoiceOver announcement posted when a rider-initiated refresh finishes and the departure times have been updated.")
    private static let filterChangedAnnouncement = OBALoc("stop_page.a11y.filter_changed", value: "Departure filter changed", comment: "VoiceOver announcement posted when the Departure Type filter changes which departures are visible.")
    private static let routesFilteredAnnouncement = OBALoc("stop_page.a11y.routes_filtered", value: "Showing filtered routes", comment: "VoiceOver announcement posted when the route filter is turned on.")
    private static let routesAllAnnouncement = OBALoc("stop_page.a11y.routes_all", value: "Showing all routes", comment: "VoiceOver announcement posted when the route filter is turned off.")
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
