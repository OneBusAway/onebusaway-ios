//
//  StopDeparturesSections.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The Stop page sections every presentation renders, in the order they all
/// render them: survey, donation, service alerts, mode toggle, departures,
/// footer.
///
/// Returns several `Section`s from one body — the shape `ServiceAlertsSection`
/// already uses — so callers drop it straight into their own `List` and keep
/// ownership of the header and chrome above it.
///
/// A plain-value view: it never touches `StopViewModel`.
struct StopDeparturesSections: View {

    let content: StopPageContent

    let survey: Survey?
    let stopID: StopID
    let serviceAlerts: [ServiceAlert]
    let sortType: StopSort
    let walkMinutes: Int?
    let minutesAfter: UInt
    let isBrokenBookmark: Bool
    let errorText: String?
    let showsDonation: Bool
    let isLoadMoreExhausted: Bool
    let isLoading: Bool

    let pastCollapsed: Bool
    let expandedRouteID: RouteID?

    let statusProvider: (ArrivalDeparture) -> DepartureStatus
    let alarmLookup: (ArrivalDeparture) -> Alarm?
    let alarmLeadTime: (Alarm) -> Int
    let canAlarm: (ArrivalDeparture) -> Bool
    let actionsProvider: (ArrivalDeparture) -> DepartureRowActions

    let onSurveyNext: (String) -> Void
    let onSurveyDismiss: () -> Void
    let onSurveyExternal: () -> Void
    let onDonate: () -> Void
    let onDonationClose: () -> Void
    let onSelectAlert: (ServiceAlert) -> Void
    let onChangeMode: (StopSort) -> Void
    let onTogglePast: () -> Void
    let onToggleRoute: (RouteID) -> Void
    let onSelectDeparture: (ArrivalDeparture) -> Void
    let onAlarmToggle: (ArrivalDeparture) -> Void
    let onRetry: () -> Void
    let onShowAllRoutes: () -> Void
    let onShowAllDepartureTypes: () -> Void
    let onLoadMore: () -> Void

    /// Leading/trailing inset shared by the page's full-width card rows,
    /// matching the inset-grouped card margin.
    private static let horizontalRowInset: CGFloat = 0

    /// The survey card draws its own rounded background, so unlike the other
    /// card rows it needs a margin: flush with the screen edges, its corners fall
    /// off-screen and the card reads as a stray hairline band.
    private static let surveyRowInset: CGFloat = 16

    var body: some View {
        // Hoisted for the same reason `walkMinutes` is passed in rather than
        // recomputed: the header row's Past count and the list's past section
        // have to be reading the same partition.
        let chronologicalPartition = StopPageListBuilder.chronologicalPartition(
            content.departures,
            walkMinutes: walkMinutes
        )

        if let survey {
            Section {
                SurveyCardRepresentable(
                    survey: survey,
                    stopID: stopID,
                    onNext: onSurveyNext,
                    onDismiss: onSurveyDismiss,
                    onOpenExternalSurvey: onSurveyExternal
                )
                .listRowInsets(EdgeInsets(top: 8, leading: Self.surveyRowInset, bottom: 8, trailing: Self.surveyRowInset))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }

        // Inline donation request (parity with the legacy UIKit
        // `DonationListItem`). Sits after the survey and before service alerts,
        // matching the legacy section order.
        if showsDonation {
            Section {
                DonationCardRepresentable(
                    onDonate: onDonate,
                    onLearnMore: onDonate,
                    onClose: onDonationClose
                )
                .listRowInsets(EdgeInsets(top: 4, leading: Self.horizontalRowInset, bottom: 4, trailing: Self.horizontalRowInset))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }

        if !serviceAlerts.isEmpty {
            ServiceAlertsSection(alerts: serviceAlerts, onSelect: onSelectAlert)
        }

        if content.hasLoadedArrivals {
            Section {
                StopPageListHeaderRow(
                    mode: sortType,
                    // Grouped mode has no past partition, so it has nothing to disclose.
                    pastCount: content.isGrouped ? 0 : chronologicalPartition.past.count,
                    showPast: !pastCollapsed,
                    onTogglePast: onTogglePast,
                    onChangeMode: onChangeMode
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }

        if content.listIsEmpty {
            if content.showsLoadingState {
                Section {
                    StopPageLoadingRow()
                }
            } else {
                Section {
                    StopPageEmptyStateRow(
                        isBrokenBookmark: isBrokenBookmark,
                        errorText: errorText,
                        isFilteredEmpty: content.isFilteredEmpty,
                        isDepartureFilterEmpty: content.isDepartureFilterEmpty,
                        minutesAfter: minutesAfter,
                        fillsPage: content.fillsPage,
                        onRetry: onRetry,
                        onShowAllRoutes: onShowAllRoutes,
                        onShowAllDepartureTypes: onShowAllDepartureTypes
                    )
                }
            }
        } else if !content.isGrouped {
            ChronologicalListView(
                // Same value the header row counts its Past disclosure from — two
                // derivations of the same partition could disagree about whether
                // there is anything to disclose.
                partition: chronologicalPartition,
                walkMinutes: walkMinutes,
                showPast: !pastCollapsed,
                statusProvider: statusProvider,
                alarmLookup: alarmLookup,
                actionsProvider: actionsProvider,
                onSelectDeparture: onSelectDeparture
            )
        } else {
            GroupedListView(
                groups: content.routeGroups,
                expandedRouteID: expandedRouteID,
                statusProvider: statusProvider,
                alarmLookup: alarmLookup,
                alarmLeadTime: alarmLeadTime,
                canAlarm: canAlarm,
                onToggleRoute: onToggleRoute,
                onSelectDeparture: onSelectDeparture,
                onAlarmToggle: onAlarmToggle
            )
        }

        if content.hasLoadedArrivals {
            StopPageFooterSection(
                showLoadMore: !isLoadMoreExhausted,
                isLoading: isLoading,
                attribution: content.attributionText,
                onLoadMore: onLoadMore
            )
        }
    }
}
