//
//  BookmarksListView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Everything that navigates away from — or presents a modal over — the
/// Bookmarks tab, implemented by the hosting `BookmarksViewController` so the
/// SwiftUI layer stays router-free and holds no `Application` reference.
struct BookmarksNavigationHandler {
    /// Pushes the stop page for a tapped bookmark, carrying bookmark context.
    let selectBookmark: (Bookmark) -> Void
    /// Presents the bookmark editor modal (row context menu).
    let editBookmark: (Bookmark) -> Void
    /// Deletes the bookmark, reporting analytics first (row context menu; the
    /// menu's nested confirm step has already happened by the time this runs).
    let deleteBookmark: (Bookmark) -> Void
    /// Starts a Live Activity tracking the bookmark on the Lock Screen.
    let trackBookmark: (Bookmark) -> Void
    /// Whether the system allows starting Live Activities; gates the Track item.
    let liveActivitiesEnabled: () -> Bool
    /// Drives pull-to-refresh: kicks off a batch, returns when it completes,
    /// and fires the completion haptic.
    let refresh: () async -> Void
    /// Lazily builds the row long-press stop-page preview.
    let makeStopPreview: (StopID) -> AnyView
}

/// Thin hosting wrapper for `BookmarksListView`, mirroring `StopPageRootView`:
/// applies `.defaultAppStorage` for parity with the Stop page (no `@AppStorage`
/// consumers here yet) and injects the app's shared `Formatters`.
struct BookmarksRootView: View {
    let viewModel: BookmarksViewModel
    let userDefaults: UserDefaults
    /// Mutable so the hosting controller can install the real handler after
    /// `super.init` (closures capturing the controller can't exist before it).
    var navigation: BookmarksNavigationHandler
    let formatters: Formatters

    var body: some View {
        BookmarksListView(viewModel: viewModel, navigation: navigation)
            .defaultAppStorage(userDefaults)
            .environment(\.obaFormatters, formatters)
    }
}

/// The Bookmarks tab: collapsible group sections of trip-bookmark cards and
/// whole-stop bookmark rows.
struct BookmarksListView: View {
    @ObservedObject var viewModel: BookmarksViewModel
    let navigation: BookmarksNavigationHandler

    var body: some View {
        if viewModel.sections.isEmpty {
            let empty = viewModel.emptyState
            EmptyStateView(title: empty.title, description: empty.body, systemImage: "bookmark")
        } else {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(viewModel.sections) { section in
                Section {
                    if !viewModel.collapsedSectionIDs.contains(section.id) {
                        ForEach(section.rows) { row in
                            bookmarkRow(row)
                        }
                    }
                } header: {
                    sectionHeader(section)
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await navigation.refresh()
        }
        .sensoryFeedback(.selection, trigger: viewModel.collapsedSectionIDs)
    }

    // MARK: - Section Header

    private func sectionHeader(_ section: BookmarkListSection) -> some View {
        let collapsed = viewModel.collapsedSectionIDs.contains(section.id)
        return Button {
            withAnimation {
                viewModel.toggleSectionCollapsed(section.id)
            }
        } label: {
            HStack {
                Text(section.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .accessibilityValue(collapsed
            ? OBALoc("stop_page.grouped.a11y_collapsed", value: "collapsed", comment: "VoiceOver value of a collapsible section header when its contents are hidden.")
            : OBALoc("stop_page.grouped.a11y_expanded", value: "expanded", comment: "VoiceOver value of a collapsible section header when its contents are visible."))
    }

    // MARK: - Rows

    private func bookmarkRow(_ row: BookmarkRowViewModel) -> some View {
        Group {
            if row.isTripBookmark {
                BookmarkCardView(row: row)
            } else {
                StopBookmarkRow(row: row)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            navigation.selectBookmark(row.bookmark)
        }
        .contextMenu {
            contextMenuItems(for: row)
        } preview: {
            navigation.makeStopPreview(row.stopID)
        }
    }

    @ViewBuilder
    private func contextMenuItems(for row: BookmarkRowViewModel) -> some View {
        // Track is gated on isTripBookmark and loaded arrival data in addition
        // to the system setting — the legacy menu offered it on stop bookmarks
        // and still-loading rows too, where starting an activity always failed
        // for lack of a trip's arrival data.
        if row.isTripBookmark && !row.arrivalDepartures.isEmpty && navigation.liveActivitiesEnabled() {
            Button {
                navigation.trackBookmark(row.bookmark)
            } label: {
                Label(
                    OBALoc("bookmarks_controller.context_menu.track_live_activity", value: "Track", comment: "Action to start a Live Activity for a specific bookmark"),
                    systemImage: "waveform.circle.fill"
                )
            }
        }

        Button {
            navigation.editBookmark(row.bookmark)
        } label: {
            Label(Strings.edit, systemImage: "square.and.pencil")
        }

        // Nested menu reproduces the legacy delete → confirm two-step.
        Menu {
            Button(role: .destructive) {
                navigation.deleteBookmark(row.bookmark)
            } label: {
                Label(Strings.confirmDelete, systemImage: "trash.fill")
            }
        } label: {
            Label(
                OBALoc("bookmarks_controller.delete_bookmark.actionsheet.title", value: "Delete Bookmark", comment: "The title to display to confirm the user's action to delete a bookmark."),
                systemImage: "trash.fill"
            )
        }
    }
}
