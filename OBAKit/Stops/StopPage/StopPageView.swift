//
//  StopPageView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
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
    /// Pushes the alert-detail screen for a tapped service alert.
    let showAlertDetail: (ServiceAlert) -> Void
    /// Opens the bookmark editor: `nil` for a stop-level bookmark, an
    /// `ArrivalDeparture` for a trip-level bookmark (row swipe/menu).
    let showBookmarkEditor: (ArrivalDeparture?) -> Void
    /// Shows the "couldn't open survey" alert when an external survey link fails.
    let showExternalSurveyError: () -> Void
    /// Presents the donation learn-more/donate modal.
    let showDonation: () -> Void
    /// Presents the donation dismiss action sheet; invokes the completion when the
    /// user actually hides the card (dismiss or remind-later, not cancel).
    let dismissDonation: (@escaping () -> Void) -> Void
    /// Lazily builds the row long-press trip preview as an `AnyView`.
    let makeTripPreview: (ArrivalDeparture) -> AnyView
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

    var body: some View {
        StopPageView(
            viewModel: viewModel,
            userDefaults: userDefaults,
            snapshotLoader: snapshotLoader,
            navigation: navigation
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

    @State private var expandedDepartureID: String?
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

    private var filteredDepartures: [ArrivalDeparture] {
        let all = viewModel.stopArrivals?.arrivalsAndDepartures ?? []
        return viewModel.isListFiltered ? all.filter(preferences: viewModel.stopPreferences) : all
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
        let departures = filteredDepartures
        let departureIDs = Set(departures.map(\.id))
        let routeIDs = Set(departures.map(\.routeID))

        List {
            if let stop = viewModel.stop {
                Section {
                    StopPageHeaderView(stop: stop, walkTime: walkTime, snapshotLoader: snapshotLoader)
                        .listRowInsets(EdgeInsets(top: 0, leading: Self.horizontalRowInset, bottom: 0, trailing: Self.horizontalRowInset))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            if !viewModel.statusText.isEmpty {
                LiveStatusRow(statusText: viewModel.statusText)
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
            if viewModel.shouldRequestDonations && !donationHidden {
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

            Section {
                StopPageModeToggle(mode: viewModel.stopPreferences.sortType) { newValue in
                    withAnimation {
                        // Switching modes collapses every open accordion (§4.6).
                        expandedDepartureID = nil
                        expandedRouteID = nil
                        userDefaults.set(newValue.rawValue, forKey: Self.lastUsedStopSortKey)
                        viewModel.updateSortType(newValue)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if departures.isEmpty {
                if viewModel.isLoading {
                    Section {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    Section {
                        StopPageEmptyStateRow(
                            errorText: viewModel.operationError?.localizedDescription,
                            isFilteredEmpty: viewModel.isListFiltered && !(viewModel.stopArrivals?.arrivalsAndDepartures.isEmpty ?? true),
                            minutesAfter: viewModel.minutesAfter,
                            onRetry: { Task { await viewModel.refresh() } },
                            onShowAllRoutes: { viewModel.isListFiltered = false }
                        )
                    }
                }
            } else if viewModel.stopPreferences.sortType == .time {
                ChronologicalListView(
                    partition: StopPageListBuilder.chronologicalPartition(departures, walkMinutes: walkTime?.walkMinutes),
                    walkMinutes: walkTime?.walkMinutes,
                    showPast: !pastCollapsed,
                    expandedDepartureID: expandedDepartureID,
                    statusProvider: { DepartureStatus(arrivalDeparture: $0) },
                    alarmLookup: { viewModel.alarm(for: $0) },
                    actionsProvider: makeActions(for:),
                    onTogglePast: { withAnimation { pastCollapsed.toggle() } },
                    onToggleExpand: { departure in
                        withAnimation(.snappy) {
                            expandedDepartureID = expandedDepartureID == departure.id ? nil : departure.id
                        }
                    },
                    panelBuilder: makePanel(for:)
                )
            } else {
                GroupedListView(
                    groups: StopPageListBuilder.routeGroups(departures),
                    expandedRouteID: expandedRouteID,
                    openTripDepartureID: expandedDepartureID,
                    statusProvider: { DepartureStatus(arrivalDeparture: $0) },
                    alarmLookup: { viewModel.alarm(for: $0) },
                    alarmLeadTime: { viewModel.alarmLeadTimeMinutes($0) },
                    canAlarm: { viewModel.canCreateAlarm(for: $0) },
                    onToggleRoute: { routeID in
                        withAnimation(.snappy) {
                            expandedRouteID = expandedRouteID == routeID ? nil : routeID
                            expandedDepartureID = nil
                        }
                    },
                    onToggleTrip: { departure in
                        withAnimation(.snappy) {
                            expandedDepartureID = expandedDepartureID == departure.id ? nil : departure.id
                        }
                    },
                    onAlarmToggle: { departure in
                        Task { await viewModel.toggleAlarm(for: departure) }
                    },
                    panelBuilder: makePanel(for:)
                )
            }

            StopPageFooterSection(
                showLoadMore: !viewModel.isLoadMoreExhausted,
                attribution: attributionText,
                onLoadMore: { Task { await viewModel.loadMoreDepartures() } }
            )
        }
        // `.plain` (rather than `.insetGrouped`) so sections have no horizontal
        // card margin insetting them from the screen edges. That margin is
        // separate from `listRowInsets` (which only pads inside a row's
        // background), which is why zeroing the row insets alone left a gap.
        // With `.plain`, rows whose `listRowInsets` leading/trailing are 0 sit
        // flush with the screen edges.
        .listStyle(.plain)
        .task { await viewModel.start() }
        .onAppear(perform: seedLastUsedModeIfNeeded)
        .onDisappear { viewModel.deactivate() }
        .refreshable { await viewModel.refresh() }
        // Reconcile the open accordions against the live feed: when a refresh
        // drops the expanded departure (or its whole route) from the list,
        // clear the stale expansion so no orphaned panel lingers.
        .onChange(of: departureIDs) { _, ids in
            if let id = expandedDepartureID, !ids.contains(id) { expandedDepartureID = nil }
        }
        .onChange(of: routeIDs) { _, ids in
            if let rid = expandedRouteID, !ids.contains(rid) { expandedRouteID = nil }
        }
    }

    /// One-shot: an untouched stop (still on the default `.time` sort) opens in
    /// the last mode the user picked anywhere in the app. A stop with a
    /// persisted `.route` preference is left alone.
    private func seedLastUsedModeIfNeeded() {
        guard !didSeedMode else { return }
        didSeedMode = true
        guard viewModel.stopPreferences.sortType == .time,
              let raw = userDefaults.string(forKey: Self.lastUsedStopSortKey),
              let seeded = StopSort(rawValue: raw)
        else { return }
        viewModel.updateSortType(seeded)
    }

    /// Builds the shared trip-detail panel (§4.6) for an expanded departure.
    /// `StopPageView` is the only view that touches the VM, so the panel receives
    /// plain values plus closures — the `approachLoader` closure wraps the cached,
    /// live-only VM fetch; the alarm closures route through the single alarm index.
    private func makePanel(for departure: ArrivalDeparture) -> TripDetailPanelView {
        let status = DepartureStatus(arrivalDeparture: departure)
        let alarm = viewModel.alarm(for: departure)
        return TripDetailPanelView(
            departure: departure,
            status: status,
            alarm: alarm,
            alarmLeadTimeMinutes: alarm.map { viewModel.alarmLeadTimeMinutes($0) } ?? viewModel.defaultAlarmLeadTime,
            canAlarm: viewModel.canCreateAlarm(for: departure),
            // Bumps on every successful refresh so the panel re-fetches its
            // approach timeline while it stays open (scheduled→live flips and
            // failed first fetches retry on the next refresh).
            refreshToken: viewModel.lastUpdated,
            cachedTripDetails: viewModel.cachedApproachTripDetails(for: departure),
            approachLoader: { await viewModel.approachTripDetails(for: departure) },
            onSetAlarm: { Task { await viewModel.setAlarm(for: departure, leadTimeMinutes: viewModel.defaultAlarmLeadTime) } },
            onCancelAlarm: { Task { await viewModel.cancelAlarm(for: departure) } },
            onChangeAlarm: { minutes in Task { await viewModel.changeAlarm(for: departure, leadTimeMinutes: minutes) } },
            onSchedule: { navigation.showScheduleForRoute(departure) },
            onViewFullTrip: { navigation.showTrip(departure) }
        )
    }

    private func makeActions(for departure: ArrivalDeparture) -> DepartureRowActions {
        DepartureRowActions(
            canAlarm: viewModel.canCreateAlarm(for: departure),
            canSchedule: navigation.canScheduleForRoute,
            hasAlarm: viewModel.alarm(for: departure) != nil,
            onAlarmToggle: {
                Task { await viewModel.toggleAlarm(for: departure) }
            },
            onSchedule: { navigation.showScheduleForRoute(departure) },
            onBookmark: { navigation.showBookmarkEditor(departure) },
            onShowTrip: { navigation.showTrip(departure) },
            makePreview: { navigation.makeTripPreview(departure) }
        )
    }
}

/// The Chronological / By route switch shown above the departure list.
/// Factored into its own `View` (per the SwiftUI structure guidance and the
/// Task 9 interface) so `StopPageView` stays a thin composition — the mode
/// change side effects (collapse accordions, persist) live in the caller's
/// `onChange`.
///
/// A custom capsule control rather than a segmented `Picker`: taller segments,
/// narrower footprint, and a Liquid Glass backdrop on iOS 26+ (an
/// ultra-thin-material capsule stands in on earlier versions). The selected
/// pill slides between segments via `matchedGeometryEffect`; the caller's
/// `withAnimation` drives it.
struct StopPageModeToggle: View {
    let mode: StopSort
    let onChange: (StopSort) -> Void

    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 2) {
            segment(.time, title: OBALoc("stop_page.mode.chronological", value: "Chronological", comment: "Stop page mode toggle: flat time-sorted list"))
            segment(.route, title: OBALoc("stop_page.mode.by_route", value: "By route", comment: "Stop page mode toggle: grouped by route"))
        }
        .padding(3)
        .modifier(GlassCapsuleBackground())
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func segment(_ value: StopSort, title: String) -> some View {
        Button {
            if mode != value { onChange(value) }
        } label: {
            Text(title)
                .font(.subheadline.weight(mode == value ? .bold : .semibold))
                .foregroundStyle(mode == value ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background {
                    if mode == value {
                        Capsule()
                            .fill(Color(uiColor: .systemBackground))
                            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                            .matchedGeometryEffect(id: "selectedSegment", in: selectionNamespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == value ? [.isButton, .isSelected] : [.isButton])
    }
}

/// The toggle's backdrop: real Liquid Glass on iOS 26+, an ultra-thin-material
/// capsule with a hairline rim on earlier versions.
private struct GlassCapsuleBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5))
        }
    }
}

/// The out-of-card "Updated N min ago" line with a pulsing on-time dot. The dot
/// pulse is gated on Reduce Motion (static when reduced), per the global
/// constraints.
struct LiveStatusRow: View {
    let statusText: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(uiColor: ThemeColors.shared.departureOnTime))
                .frame(width: 7, height: 7)
                .opacity(reduceMotion ? 1 : (pulsing ? 1 : 0.35))
            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 20, bottom: 2, trailing: 20))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Service alerts affecting this stop, rendered as one self-contained,
/// orange-tinted card: a header row (gradient warning badge, title, count pill,
/// rotating chevron) that toggles expansion, with the alert rows inside the
/// card when expanded. Each alert row pushes the existing alert-detail screen
/// via the hosting VC's `onSelect` callback.
///
/// Honors the legacy `stopViewShowsServiceAlerts` preference (same UserDefaults
/// key, default collapsed): tapping the header toggles and persists it, matching
/// the legacy screen's collapsible section. When expanded and there are more
/// than two alerts, it shows the first two plus a "Show all N" row.
struct ServiceAlertsSection: View {
    let alerts: [ServiceAlert]
    let onSelect: (ServiceAlert) -> Void

    /// Legacy persisted preference; read/written through the app-group suite that
    /// `StopPageRootView` installs via `.defaultAppStorage`. Default `false`
    /// (collapsed) mirrors `StopViewController`, which registers no default for
    /// this key.
    @AppStorage("stopViewShowsServiceAlerts") private var showsServiceAlerts = false

    /// Per-visit "show all" expansion for the >2 case (not persisted).
    @State private var showAllAlerts = false

    private var visibleAlerts: [ServiceAlert] {
        showAllAlerts ? alerts : Array(alerts.prefix(2))
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    var body: some View {
        Section {
            VStack(spacing: 0) {
                headerRow
                if showsServiceAlerts {
                    ForEach(visibleAlerts) { alert in
                        Divider().padding(.leading, 14)
                        alertRow(alert)
                    }
                    if alerts.count > 2 && !showAllAlerts {
                        Divider().padding(.leading, 14)
                        showAllRow
                    }
                }
            }
            .background(cardShape.fill(Color.orange.opacity(0.08)))
            .overlay(cardShape.strokeBorder(Color.orange.opacity(0.22), lineWidth: 1))
            .clipShape(cardShape)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    /// Always-visible card header; tapping toggles (and persists) expansion.
    private var headerRow: some View {
        Button {
            withAnimation(.snappy) {
                showsServiceAlerts.toggle()
                if !showsServiceAlerts { showAllAlerts = false }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(Strings.serviceAlerts)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(alerts.count)")
                    .font(.caption.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.orange, in: Capsule())
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(showsServiceAlerts ? 180 : 0))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(headerAccessibilityLabel)
    }

    private var showAllRow: some View {
        Button {
            withAnimation { showAllAlerts = true }
        } label: {
            Text(String(format: OBALoc("stop_page.service_alerts.show_all_fmt", value: "Show all %d alerts", comment: "Row that expands the service alerts section to show every alert. %d is the total number of alerts."), alerts.count))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var headerAccessibilityLabel: String {
        alerts.count == 1
            ? OBALoc("stop_page.service_alerts.summary_one", value: "1 service alert", comment: "Collapsed summary row for the service alerts section when exactly one alert applies.")
            : String(format: OBALoc("stop_page.service_alerts.summary_fmt", value: "%d service alerts", comment: "Collapsed summary row for the service alerts section. %d is the number of alerts."), alerts.count)
    }

    private func alertRow(_ alert: ServiceAlert) -> some View {
        Button {
            onSelect(alert)
        } label: {
            HStack(spacing: 10) {
                Text(alert.title(forLocale: .current) ?? OBALoc("stop_page.service_alert_fallback", value: "Service alert", comment: "Fallback title for a service alert that has no summary text."))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The footer: "Load more" (hidden once auto-extend hits the 12 h cap) and the
/// data-attribution line.
struct StopPageFooterSection: View {
    let showLoadMore: Bool
    let attribution: String
    let onLoadMore: () -> Void

    var body: some View {
        Section {
            if showLoadMore {
                Button(action: onLoadMore) {
                    Label(
                        OBALoc("stop_page.load_more", value: "Load more", comment: "Extends the departure time window"),
                        systemImage: "plus"
                    )
                    .font(.system(size: 14.5, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
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

/// The single empty-state row shown when there are no departures to list.
/// Precedence: a network error (Retry) → everything filtered out (Show all
/// routes) → genuinely no service in the window. §4.4 wording is exact.
struct StopPageEmptyStateRow: View {
    let errorText: String?
    let isFilteredEmpty: Bool
    let minutesAfter: UInt
    let onRetry: () -> Void
    let onShowAllRoutes: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var symbolName: String {
        if errorText != nil { return "exclamationmark.icloud" }
        if isFilteredEmpty { return "line.3.horizontal.decrease.circle" }
        return "clock.badge.xmark"
    }

    private var message: String {
        if let errorText { return errorText }
        if isFilteredEmpty {
            return OBALoc("stop_page.empty.all_filtered", value: "All routes at this stop are filtered", comment: "Empty state shown when every route at the stop is hidden by the user's filter.")
        }
        let fmt = OBALoc("stop_page.empty.no_departures_fmt", value: "No departures in the next %d minutes", comment: "Empty state shown when the stop has no upcoming departures within the loaded time window. %d is the number of minutes.")
        return String(format: fmt, minutesAfter)
    }

    private var actionTitle: String? {
        if errorText != nil {
            return OBALoc("stop_page.empty.retry", value: "Retry", comment: "Button that retries loading departures after an error.")
        }
        if isFilteredEmpty {
            return OBALoc("stop_page.empty.show_all_routes", value: "Show all routes", comment: "Button that clears the route filter so all routes are shown.")
        }
        return nil
    }

    private func action() {
        if errorText != nil {
            onRetry()
        } else if isFilteredEmpty {
            onShowAllRoutes()
        }
    }
}
