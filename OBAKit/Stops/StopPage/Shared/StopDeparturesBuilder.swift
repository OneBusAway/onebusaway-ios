//
//  StopDeparturesBuilder.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Assembles `StopDeparturesSections`, the trip panel and the row actions from
/// a `StopViewModel`.
///
/// `StopDeparturesSections` takes around forty arguments, and both Stop page
/// presentations — the pushed `StopPageView` and the map's
/// `StopDetailsSheetView` — need the same forty. Building that list in each view
/// meant every departure-row behaviour existed twice: the alarm-toggle branch,
/// the collapse-accordions-on-sort-change side effect, the donation dismissal.
/// A change applied to one was invisible from the other.
///
/// So the assembly lives here instead, and the views supply only what genuinely
/// differs between them (`onRetry`, and the `@State` they own).
@MainActor
struct StopDeparturesBuilder {
    let viewModel: StopViewModel
    let navigation: StopPageNavigationHandler
    /// The app-group suite, for the "last used sort" seed the mode toggle writes.
    let userDefaults: UserDefaults

    /// The one behaviour that legitimately differs: the pushed page just
    /// refreshes, while the sheet's version holds a spinner up for a minimum
    /// duration so the tap has a visible result.
    let onRetry: () -> Void

    @Binding var expandedRouteID: RouteID?
    @Binding var donationHidden: Bool
    @Binding var pastCollapsed: Bool

    /// - Parameter walkTime: passed in rather than re-read off the view model,
    ///   so the header chip, the chronological partition and the walk divider
    ///   all render one snapshot of a value that moves with the user's location.
    func sections(content: StopPageContent, walkTime: WalkTimeInfo?) -> StopDeparturesSections {
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
            expandedRouteID: expandedRouteID,
            statusProvider: { DepartureStatus(arrivalDeparture: $0) },
            alarmLookup: { viewModel.alarm(for: $0) },
            alarmLeadTime: { viewModel.alarmLeadTimeMinutes($0) },
            canAlarm: { viewModel.canCreateAlarm(for: $0) },
            actionsProvider: makeActions(for:),
            onSurveyNext: submitSurveyAnswer(_:),
            onSurveyDismiss: { viewModel.dismissCurrentSurvey() },
            onSurveyExternal: launchExternalSurvey,
            onDonate: navigation.showDonation,
            onDonationClose: hideDonation,
            onSelectAlert: navigation.showAlertDetail,
            onChangeMode: change(sortType:),
            onTogglePast: togglePast,
            onToggleRoute: toggleExpandedRoute(_:),
            onSelectDeparture: navigation.showTrip,
            onAlarmToggle: toggleAlarm(for:),
            onRetry: onRetry,
            onShowAllRoutes: { viewModel.isListFiltered = false },
            onShowAllDepartureTypes: { viewModel.updateArrivalDepartureFilter(.all) },
            onLoadMore: loadMore
        )
    }

    // MARK: - List actions

    private func submitSurveyAnswer(_ answer: String) {
        Task { await viewModel.submitHeroAnswer(answer, stopLocation: viewModel.stop?.coordinate) }
    }

    private func launchExternalSurvey() {
        viewModel.launchExternalSurvey(viewModel.currentSurvey, onFailure: navigation.showExternalSurveyError)
    }

    /// Drops the card as soon as the user actually hides it, rather than waiting
    /// for the next refresh to re-read `shouldRequestDonations`.
    private func hideDonation() {
        navigation.dismissDonation { donationHidden = true }
    }

    /// Switching modes collapses the open route card, then persists the choice
    /// as the app-wide "last used" seed.
    private func change(sortType: StopSort) {
        withAnimation {
            expandedRouteID = nil
            userDefaults.set(sortType.rawValue, forKey: StopPageLifecycleKeys.lastUsedStopSort)
            viewModel.updateSortType(sortType)
        }
    }

    private func togglePast() {
        withAnimation { pastCollapsed.toggle() }
    }

    private func toggleExpandedRoute(_ routeID: RouteID) {
        withAnimation(.snappy) {
            expandedRouteID = expandedRouteID == routeID ? nil : routeID
        }
    }

    private func toggleAlarm(for departure: ArrivalDeparture) {
        if viewModel.alarm(for: departure) != nil {
            Task { await viewModel.cancelAlarm(for: departure) }
        } else {
            navigation.showAlarmPicker(departure)
        }
    }

    private func loadMore() {
        Task { await viewModel.loadMoreDepartures() }
    }

    // MARK: - Row plumbing

    func makeActions(for departure: ArrivalDeparture) -> DepartureRowActions {
        DepartureRowActions(
            canAlarm: viewModel.canCreateAlarm(for: departure),
            canSchedule: navigation.canScheduleForRoute,
            hasAlarm: viewModel.alarm(for: departure) != nil,
            onAlarmToggle: { toggleAlarm(for: departure) },
            onSchedule: { navigation.showScheduleForRoute(departure) },
            onBookmark: { navigation.showBookmarkEditor(departure) },
            onShowTrip: { navigation.showTrip(departure) },
            onShareTrip: { navigation.shareTrip(departure) },
            makePreview: { navigation.makeTripPreview(departure) }
        )
    }
}
