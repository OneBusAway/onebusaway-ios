//
//  RecentStopsListView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Navigation and external actions emitted by `RecentStopsListView`, fulfilled by
/// `RecentStopsViewController` so the SwiftUI view stays router-free and holds no
/// `Application` reference.
struct RecentStopsNavigationHandler {
    let selectStop: (Stop) -> Void
    let selectAlarm: (RecentStopsViewController.AlarmViewModel) -> Void
    let deleteAlarm: (RecentStopsViewController.AlarmViewModel) -> Void
    let exploreMap: () -> Void
    let makeStopPreview: (StopID) -> AnyView
}

/// The Recent tab: displays active arrival alarms (when present) and recently
/// viewed transit stops, with swipe actions for quick bookmarking and deletion.
struct RecentStopsListView: View {
    @ObservedObject var viewModel: RecentStopsViewModel
    let navigation: RecentStopsNavigationHandler

    var alarmRows: [RecentStopsViewController.AlarmViewModel] {
        viewModel.alarms.compactMap { alarm in
            RecentStopsViewController.AlarmViewModel(
                withAlarm: alarm,
                onSelect: navigation.selectAlarm,
                onDelete: navigation.deleteAlarm
            )
        }
    }

    var isShowingEmptyState: Bool {
        alarmRows.isEmpty && viewModel.recentStops.isEmpty
    }

    var stopsSectionTitle: String? {
        alarmRows.isEmpty ? nil : Strings.recentStops
    }

    var body: some View {
        if isShowingEmptyState {
            emptyStateView
        } else {
            list
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            if !alarmRows.isEmpty {
                Section {
                    ForEach(alarmRows, id: \.id) { alarmRow in
                        alarmRowView(alarmRow)
                    }
                } header: {
                    Text(OBALoc(
                        "recent_stops_controller.alarms_section.title",
                        value: "Alarms",
                        comment: "Title of the Alarms section of the Recents controller"
                    ))
                }
                .textCase(nil)
            }

            if !viewModel.recentStops.isEmpty {
                if let title = stopsSectionTitle {
                    Section {
                        recentStopRows
                    } header: {
                        Text(title)
                    }
                    .textCase(nil)
                } else {
                    Section {
                        recentStopRows
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var recentStopRows: some View {
        ForEach(viewModel.recentStops, id: \.id) { stop in
            stopRowView(stop)
        }
    }

    // MARK: - Rows

    private func alarmRowView(_ alarmRow: RecentStopsViewController.AlarmViewModel) -> some View {
        Button {
            navigation.selectAlarm(alarmRow)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bell.fill")
                    .foregroundStyle(Color(uiColor: ThemeColors.shared.brand))
                    .accessibilityHidden(true)

                Text(alarmRow.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                Spacer()

                Image(systemName: "chevron.forward")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(uiColor: ThemeColors.shared.brand))
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(Strings.delete, role: .destructive) {
                navigation.deleteAlarm(alarmRow)
            }
        }
    }

    private func stopRowView(_ stop: Stop) -> some View {
        let isBookmarked = viewModel.isBookmarked(stop)

        return HomeStopRow(stop: stop) {
            navigation.selectStop(stop)
        }
        .recentStopSwipeActions(for: stop, viewModel: viewModel)
        .contextMenu {
            Button {
                viewModel.toggleBookmark(for: stop)
            } label: {
                RecentStopBookmarkLabel(isBookmarked: isBookmarked)
            }

            Button(role: .destructive) {
                viewModel.delete(recentStop: stop)
            } label: {
                Label(Strings.delete, systemImage: "trash")
            }
        } preview: {
            navigation.makeStopPreview(stop.id)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        EmptyStateView(
            title: OBALoc(
                "recent_stops.empty_set.title",
                value: "No Recent Stops",
                comment: "Title for the empty set indicator on the Recent Stops controller."
            ),
            description: OBALoc(
                "recent_stops.empty_set.body",
                value: "Transit stops that you view in the app will appear here.",
                comment: "Body for the empty set indicator on the Recent Stops controller."
            ),
            systemImage: "clock"
        ) {
            Button {
                navigation.exploreMap()
            } label: {
                Label(
                    OBALoc(
                        "recent_stops.empty_set.button",
                        value: "Find Stops on Maps",
                        comment: "The button title for taking the user to the map view to find stops."
                    ),
                    systemImage: "map"
                )
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Shared Recent Stop Actions

/// Label for adding or removing a quick stop bookmark, shared by swipe actions
/// and row context menus.
struct RecentStopBookmarkLabel: View {
    let isBookmarked: Bool

    var body: some View {
        if isBookmarked {
            Label(
                OBALoc(
                    "bookmarks_controller.delete_bookmark.actionsheet.title",
                    value: "Delete Bookmark",
                    comment: "The title to display to confirm the user's action to delete a bookmark."
                ),
                systemImage: "bookmark.slash"
            )
        } else {
            Label(Strings.bookmark, systemImage: "bookmark")
        }
    }
}

extension View {
    /// Leading quick-bookmark toggle and trailing destructive delete swipe
    /// actions shared by `RecentStopsListView` and `RecentStopsSheetView`.
    func recentStopSwipeActions(for stop: Stop, viewModel: RecentStopsViewModel) -> some View {
        let isBookmarked = viewModel.isBookmarked(stop)

        return self
            .swipeActions(edge: .leading) {
                Button {
                    viewModel.toggleBookmark(for: stop)
                } label: {
                    RecentStopBookmarkLabel(isBookmarked: isBookmarked)
                }
                .tint(isBookmarked ? .orange : Color(uiColor: ThemeColors.shared.brand))
            }
            .swipeActions(edge: .trailing) {
                Button(Strings.delete, role: .destructive) {
                    viewModel.delete(recentStop: stop)
                }
            }
    }
}
