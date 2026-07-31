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

    private let presenter: StopPageActionPresenter
    private let feedback: DataLoadFeedbackGenerator
    private let formatters: Formatters
    private let userDefaults: UserDefaults

    @State private var expandedDepartureID: String?
    @State private var expandedRouteID: RouteID?
    @State private var donationHidden = false
    @State private var collapseProgress: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
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
        // The metric is `contentOffset.y + contentInsets.top`, not
        // `contentOffset.y`. The chrome below lives in a `safeAreaInset` whose
        // height shrinks as `collapseProgress` rises; that shrink shifts the
        // content offset, which would feed back into progress and oscillate.
        // The sum holds steady when the inset changes, breaking the loop.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            collapseProgress = StopSheetHeaderCollapse.progress(
                scrollOffset: offset,
                collapsibleHeight: headerHeight
            )
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            chrome(showsLoadingState: content.showsLoadingState)
        }
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

    @ViewBuilder
    private func chrome(showsLoadingState: Bool) -> some View {
        VStack(spacing: 0) {
            StopDetailsSheetTopBar(
                title: viewModel.stop?.name ?? "",
                titleOpacity: Double(collapseProgress),
                statusText: viewModel.statusText,
                isRefreshing: viewModel.isLoading,
                onRefresh: { Task { await viewModel.refresh() } },
                onClose: { coordinator.pop() }
            )

            collapsibleHeader(showsLoadingState: showsLoadingState)

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
                    // pushed presentation's `filterMenu()` — otherwise choosing
                    // it on a stop with no saved hidden routes silently does
                    // nothing.
                    if filtered { navigation.showRouteFilter() }
                },
                onBookmark: { navigation.showBookmarkEditor(nil) },
                onServiceAlerts: navigation.showServiceAlerts,
                onNearbyStops: navigation.showNearbyStops,
                onWalkingDirections: navigation.showWalkingDirections,
                onReportProblem: navigation.showReportProblem
            )
        }
    }

    /// The pushed screen's dark map card, shrinking to nothing as the list
    /// scrolls. Its natural height is measured rather than assumed: it is
    /// `@ScaledMetric` and grows further when route chips wrap, so a constant
    /// would mis-collapse at most Dynamic Type sizes.
    ///
    /// No implicit animation here — the collapse follows the finger, and
    /// animating a value already driven by a continuous gesture is what makes
    /// this pattern jitter.
    @ViewBuilder
    private func collapsibleHeader(showsLoadingState: Bool) -> some View {
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
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            // Only record the natural height — once collapsing starts the
            // measured height is the scaled one, which would shrink the range
            // toward zero and snap the header shut.
            if collapseProgress == 0, newHeight > 0 {
                headerHeight = newHeight
            }
        }
        .frame(height: max(headerHeight * (1 - collapseProgress), 0), alignment: .top)
        .opacity(Double(1 - collapseProgress))
        .clipped()
        .accessibilityHidden(collapseProgress > 0.5)
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
