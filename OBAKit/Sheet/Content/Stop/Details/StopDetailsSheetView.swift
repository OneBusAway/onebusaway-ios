//
//  StopDetailsSheetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore
import ActivityKit

/// The Stop page as a native SwiftUI sheet over the map panel.
///
/// It renders the same departures as the pushed screen — through the shared
/// `StopDeparturesSections` — but replaces the navigation bar with a pinned
/// Refresh/Close strip and a row of circular actions, and collapses the map
/// header away as the list scrolls so the actions stay reachable.
///
/// This is the only view here that observes `StopViewModel`; the header, the
/// action row and the sections all take plain values, so the view model's
/// refresh and status-timer churn re-evaluates one shallow body.
struct StopDetailsSheetView: View {
    /// The stop this sheet was built for. Stored rather than read off the view
    /// model because the model lives in a `@StateObject` that SwiftUI only
    /// instantiates at render time — this is what identifies the view before
    /// then, both in debug output and to the factory's tests.
    let stopID: StopID

    @StateObject private var viewModel: StopViewModel
    @EnvironmentObject private var coordinator: SheetCoordinator<AppSheetRoute>
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let presenter: StopPageActionPresenter
    private let feedback: DataLoadFeedbackGenerator
    private let formatters: Formatters
    private let userDefaults: UserDefaults

    @State private var expandedDepartureID: String?
    @State private var expandedRouteID: RouteID?
    @State private var donationHidden = false
    /// How far the title has faded into the pinned bar, 0...1. Drives opacity
    /// ONLY — never layout. See the note on `titleFadeDistance`.
    @State private var titleProgress: CGFloat = 0
    /// Distance scrolled from the top. Drives the action row's overlay position
    /// and the title fade — never any layout the scroll view can observe.
    @State private var scrollOffset: CGFloat = 0
    /// Measured heights feeding the sticky-overlay arithmetic. None of them
    /// depend on `scrollOffset`, which is what keeps the overlay acyclic.
    @State private var topBarHeight: CGFloat = 0
    @State private var mapCardHeight: CGFloat = 0
    @State private var actionRowHeight: CGFloat = 0
    @State private var userActivity: NSUserActivity?
    /// Gates the one-shot success haptic to the first arrivals load, matching
    /// `StopViewController.bindArrivalsSink()`; later refreshes are silent.
    @State private var firstLoad = true

    @AppStorage("StopViewController.pastDeparturesCollapsed") private var pastCollapsed = true

    init(
        stopID: StopID,
        viewModel: @autoclosure @escaping () -> StopViewModel,
        presenter: StopPageActionPresenter,
        feedback: DataLoadFeedbackGenerator,
        formatters: Formatters,
        userDefaults: UserDefaults
    ) {
        self.stopID = stopID
        _viewModel = StateObject(wrappedValue: viewModel())
        self.presenter = presenter
        self.feedback = feedback
        self.formatters = formatters
        self.userDefaults = userDefaults
    }

    private var navigation: StopPageNavigationHandler {
        presenter.makeNavigationHandler(viewModel: viewModel, closeSheet: { coordinator.pop() })
    }

    var body: some View {
        let content = StopPageContent(viewModel: viewModel)
        let walkTime = viewModel.walkTime

        List {
            headerRows(showsLoadingState: content.showsLoadingState)

            StopDeparturesSections(
                content: content,
                survey: viewModel.currentSurvey,
                stopID: viewModel.stopID,
                serviceAlerts: viewModel.stopArrivals?.serviceAlerts ?? [],
                sortType: viewModel.stopPreferences.sortType,
                walkMinutes: walkTime?.walkMinutes,
                minutesAfter: viewModel.minutesAfter,
                isBrokenBookmark: viewModel.isBrokenBookmark,
                errorText: viewModel.operationErrorMessage,
                showsDonation: content.hasLoadedArrivals && viewModel.shouldRequestDonations && !donationHidden,
                isLoadMoreExhausted: viewModel.isLoadMoreExhausted,
                isLoading: viewModel.isLoading,
                pastCollapsed: pastCollapsed,
                expandedDepartureID: expandedDepartureID,
                expandedRouteID: expandedRouteID,
                statusProvider: { DepartureStatus(arrivalDeparture: $0) },
                alarmLookup: { viewModel.alarm(for: $0) },
                alarmLeadTime: { viewModel.alarmLeadTimeMinutes($0) },
                canAlarm: { viewModel.canCreateAlarm(for: $0) },
                actionsProvider: makeActions(for:),
                panelBuilder: makePanel(for:),
                onSurveyNext: { answer in
                    Task { await viewModel.submitHeroAnswer(answer, stopLocation: viewModel.stop?.coordinate) }
                },
                onSurveyDismiss: { viewModel.dismissCurrentSurvey() },
                onSurveyExternal: {
                    viewModel.launchExternalSurvey(viewModel.currentSurvey, onFailure: navigation.showExternalSurveyError)
                },
                onDonate: navigation.showDonation,
                onDonationClose: { navigation.dismissDonation { donationHidden = true } },
                onSelectAlert: navigation.showAlertDetail,
                onChangeMode: { newValue in
                    withAnimation {
                        expandedDepartureID = nil
                        expandedRouteID = nil
                        userDefaults.set(newValue.rawValue, forKey: StopPageLifecycleKeys.lastUsedStopSort)
                        viewModel.updateSortType(newValue)
                    }
                },
                onTogglePast: { withAnimation { pastCollapsed.toggle() } },
                onToggleExpand: { departure in
                    withAnimation(.snappy) {
                        expandedDepartureID = expandedDepartureID == departure.id ? nil : departure.id
                    }
                },
                onToggleRoute: { routeID in
                    withAnimation(.snappy) {
                        expandedRouteID = expandedRouteID == routeID ? nil : routeID
                        expandedDepartureID = nil
                    }
                },
                onAlarmToggle: { departure in
                    if viewModel.alarm(for: departure) != nil {
                        Task { await viewModel.cancelAlarm(for: departure) }
                    } else {
                        navigation.showAlarmPicker(departure)
                    }
                },
                onRetry: { Task { await viewModel.refresh() } },
                onShowAllRoutes: { viewModel.isListFiltered = false },
                onLoadMore: { Task { await viewModel.loadMoreDepartures() } }
            )
        }
        .listStyle(.plain)
        // No `.refreshable`: this presentation refreshes from the top bar's
        // button only, which is why that button stays pinned.
        //
        // Scroll position drives the title's OPACITY and nothing else. It must
        // never drive the height of the `safeAreaInset` below: an inset whose
        // height depends on scroll position feeds back on itself. Measured on
        // device, collapsing a 170pt header shifted
        // `contentOffset.y + contentInsets.top` by exactly 170 — so the metric
        // is not inset-invariant, and any mid-range progress oscillates
        // (progress -> inset -> offset -> progress) until the main thread is
        // pegged and the whole app stops responding.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            scrollOffset = offset
            titleProgress = StopSheetHeaderCollapse.progress(
                scrollOffset: offset,
                collapsibleHeight: Self.titleFadeDistance
            )
        }
        // Fixed height — it holds only the top bar, so nothing here resizes as
        // the list scrolls.
        .safeAreaInset(edge: .top, spacing: 0) {
            StopDetailsSheetTopBar(
                title: viewModel.stop?.name ?? "",
                titleOpacity: Double(titleProgress),
                statusText: viewModel.statusText,
                isRefreshing: viewModel.isLoading,
                onRefresh: { Task { await viewModel.refresh() } },
                onClose: { coordinator.pop() }
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topBarHeight = $0 }
        }
        // The action row rides as an overlay rather than list content or a
        // second inset. An overlay takes no part in the list's layout, so its
        // position can track scrolling without the scroll view ever observing
        // the result — the property the collapsing header lacked.
        .overlay(alignment: .top) { actionRowOverlay }
        .stopPageLifecycle(
            viewModel: viewModel,
            userDefaults: userDefaults,
            liveActivityStarted: viewModel.liveActivityStarted
        )
        .keepsScreenAwake()
        .defaultAppStorage(userDefaults)
        .environment(\.obaFormatters, formatters)
        .onChange(of: content.departureIDs) { _, ids in
            if let id = expandedDepartureID, !ids.contains(id) { expandedDepartureID = nil }
        }
        .onChange(of: content.routeIDs) { _, ids in
            if let rid = expandedRouteID, !ids.contains(rid) { expandedRouteID = nil }
        }
        .onReceive(viewModel.$stop.compactMap { $0 }) { stop in
            userActivity?.invalidate()
            let activity = presenter.makeUserActivity(stop: stop)
            activity?.becomeCurrent()
            userActivity = activity
        }
        .onReceive(viewModel.$stopArrivals.compactMap { $0 }) { _ in
            guard firstLoad else { return }
            firstLoad = false
            feedback.dataLoad(.success)
        }
        .onReceive(viewModel.$operationError.compactMap { $0 }) { _ in
            feedback.dataLoad(.failed)
        }
        .onReceive(viewModel.presentFullSurvey) { payload in
            presenter.showFullSurvey(
                payload.survey,
                heroResponseID: payload.heroResponseID,
                stop: viewModel.stop,
                stopID: viewModel.stopID
            )
        }
        .onReceive(viewModel.surveySubmissionError) { error in
            presenter.showError(error)
        }
        .onReceive(viewModel.$alarmError.compactMap { $0 }) { error in
            presenter.showError(error)
        }
        .onReceive(viewModel.$alarmPermissionDenied.dropFirst().filter { $0 }) { _ in
            presenter.showAlarmPermissionDeniedAlert {
                // Reset so a later already-denied attempt re-fires the binding.
                viewModel.clearAlarmPermissionDenied()
            }
        }
        .onChange(of: scenePhase) { previous, phase in
            switch phase {
            case .active:
                // Only re-arm on the .background → .active edge.
                // `.inactive → .active` (returning from Control Center or a
                // banner) never stopped the timer, so re-arming would issue a
                // redundant network call.
                if previous == .background {
                    Task { await viewModel.start() }
                }
            case .background:
                viewModel.deactivate()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onDisappear {
            userActivity?.invalidate()
            userActivity = nil
        }
    }

    // MARK: - Chrome

    /// Distance scrolled, in points, over which the stop name fades into the
    /// pinned bar. A plain constant: it drives opacity only, so it never needs
    /// to match the header's real height, and keeping it out of layout is what
    /// makes the fade safe.
    private static let titleFadeDistance: CGFloat = 120

    /// The map card and the action row, rendered as the list's leading rows.
    ///
    /// They deliberately scroll with the content rather than living in the
    /// pinned `safeAreaInset`. Pinning them meant the inset had to shrink as the
    /// list scrolled, and an inset whose height depends on scroll position
    /// drives an oscillation that hangs the main thread — see the note on
    /// `onScrollGeometryChange` above.
    /// The map card, plus a spacer standing in for the action row.
    ///
    /// The action row itself is an overlay (see `actionRowOverlay`), so the list
    /// needs a gap of the same height here or the first departures would sit
    /// underneath it at rest.
    @ViewBuilder
    private func headerRows(showsLoadingState: Bool) -> some View {
        Section {
            Group {
                if let stop = viewModel.stop {
                    StopPageHeaderView(
                        stop: stop,
                        walkTime: viewModel.walkTime,
                        statusText: viewModel.statusText,
                        snapshotLoader: { size in
                            await presenter.loadSnapshot(stop: stop, size: size, traitCollection: UITraitCollection.current)
                        },
                        onWalkingDirections: navigation.showWalkingDirections
                    )
                } else if showsLoadingState {
                    StopPageHeaderPlaceholderView()
                }
            }
            // Safe to measure: the card's height is a function of Dynamic Type
            // and how many route chips wrap, never of scroll position.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { mapCardHeight = $0 }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Color.clear
                .frame(height: actionRowHeight)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityHidden(true)
        }
    }

    /// Where the action row sits, measured from the top of the sheet.
    ///
    /// At rest it clears the top bar and the map card, putting it directly under
    /// the card. As the list scrolls it rises until it reaches the bar, then
    /// stops — the card slides beneath it. Rubber-banding past the top yields a
    /// negative `scrollOffset`, which pushes the row further down with the
    /// stretch, which is the natural behaviour.
    private var actionRowOffset: CGFloat {
        topBarHeight + max(0, mapCardHeight - scrollOffset)
    }

    private var actionRowOverlay: some View {
        StopPageActionRow(
            state: StopPageActionRowState(
                routeCount: viewModel.stop?.routes.count ?? 0,
                hasHiddenRoutes: viewModel.stopPreferences.hasHiddenRoutes,
                isListFiltered: viewModel.isListFiltered,
                hasServiceAlerts: !(viewModel.stopArrivals?.serviceAlerts ?? []).isEmpty
            ),
            onSchedule: navigation.showScheduleForStop,
            onSetListFiltered: { filtered in
                viewModel.isListFiltered = filtered
                // Picking "Filtered Routes" opens the picker, matching the
                // pushed presentation's `filterMenu()` — otherwise choosing it
                // on a stop with no saved hidden routes silently does nothing.
                if filtered { navigation.showRouteFilter() }
            },
            onBookmark: { navigation.showBookmarkEditor(nil) },
            onServiceAlerts: navigation.showServiceAlerts,
            onNearbyStops: navigation.showNearbyStops,
            onWalkingDirections: navigation.showWalkingDirections,
            onReportProblem: navigation.showReportProblem
        )
        // Feeds the spacer above, so the two stay the same height as Dynamic
        // Type changes.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { actionRowHeight = $0 }
        .offset(y: actionRowOffset)
    }

    // MARK: - Row plumbing

    private func makePanel(for departure: ArrivalDeparture) -> TripDetailPanelView {
        TripDetailPanelView(
            departure: departure,
            status: DepartureStatus(arrivalDeparture: departure),
            alarm: nil,
            alarmLeadTimeMinutes: 0,
            canAlarm: ActivityAuthorizationInfo().areActivitiesEnabled,
            refreshToken: viewModel.lastUpdated,
            cachedTripDetails: viewModel.cachedApproachTripDetails(for: departure),
            approachLoader: { await viewModel.approachTripDetails(for: departure) },
            onSetAlarm: { navigation.startLiveActivity(departure) },
            onCancelAlarm: {},
            onChangeAlarm: {},
            canSchedule: navigation.canScheduleForRoute,
            onSchedule: { navigation.showScheduleForRoute(departure) },
            onBookmark: { navigation.showBookmarkEditor(departure) },
            onViewFullTrip: { navigation.showTrip(departure) }
        )
    }

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
            makePreview: { navigation.makeTripPreview(departure) }
        )
    }
}
