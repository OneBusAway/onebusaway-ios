//
//  BookmarksSheetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import ActivityKit
import OBAKitCore

/// The Bookmarks index — `AppSheetRoute.bookmarksAll`.
///
/// Renders `BookmarksListView` unchanged, so group sections, collapse state,
/// pull-to-refresh, and the row context menu can't drift from the Bookmarks
/// tab. Only the navigation handler differs: taps stack `.stopDetails` on the
/// sheet coordinator instead of pushing through `viewRouter`.
///
/// Manage Bookmarks/Groups is deliberately not offered here — that stays a
/// tab-level editing surface.
struct BookmarksSheetView: View {
    let application: Application

    @StateObject private var viewModel: BookmarksViewModel
    @EnvironmentObject var coordinator: SheetCoordinator<AppSheetRoute>
    @Environment(\.dismiss) private var dismiss

    @State private var editingBookmark: Bookmark?
    @State private var isShowingTrackError = false

    /// A refresh the user asked for, as opposed to the 30 s poll `start()`
    /// installs. Deliberately not `viewModel.isLoading`, which the background
    /// poll also raises — a toolbar spinner appearing every 30 seconds on its
    /// own would read as the screen doing something the user didn't ask for.
    @State private var isRefreshing = false

    /// How long the spinner stays up at minimum. A batch served from cache can
    /// finish in a few milliseconds; without a floor the spinner would appear
    /// and vanish inside one or two frames, leaving the user unsure the tap
    /// registered at all.
    private static let minimumSpinnerDuration: Duration = .milliseconds(300)

    private let actions: BookmarkActions
    private let feedback: DataLoadFeedbackGenerator

    init(application: Application) {
        self.application = application
        self.actions = BookmarkActions(application: application)
        self.feedback = DataLoadFeedbackGenerator(application: application)
        _viewModel = StateObject(wrappedValue: BookmarksViewModel(application: application))
    }

    /// Builds the handler the list is driven by. Static and fully injected so
    /// the wiring is assertable without a `UIHostingController` — the same
    /// reasoning as `MoreSheetHost.makeNavigationController`.
    ///
    /// Presentation stays with the caller: `onEdit` and `onTrackFailure` are how
    /// this view raises its own SwiftUI sheet and alert.
    static func makeNavigationHandler(
        application: Application,
        viewModel: BookmarksViewModel,
        actions: BookmarkActions,
        coordinator: SheetCoordinator<AppSheetRoute>,
        feedback: DataLoadFeedbackGenerator,
        onEdit: @escaping (Bookmark) -> Void,
        onTrackFailure: @escaping () -> Void
    ) -> BookmarksNavigationHandler {
        BookmarksNavigationHandler(
            selectBookmark: { bookmark in
                coordinator.push(.stopDetails(stopID: bookmark.stopID))
            },
            editBookmark: onEdit,
            deleteBookmark: { bookmark in
                actions.reportDeletion(of: bookmark)
                viewModel.deleteBookmark(bookmark)
            },
            trackBookmark: { bookmark in
                let arrivals = viewModel.arrivalDepartures(for: bookmark)
                if actions.startLiveActivity(for: bookmark, arrivalDepartures: arrivals) == .failed {
                    onTrackFailure()
                }
            },
            togglePin: { bookmark in
                application.userDataStore.setPinned(!bookmark.isPinned, for: bookmark)
            },
            liveActivitiesEnabled: { ActivityAuthorizationInfo().areActivitiesEnabled },
            refresh: {
                await viewModel.refreshAndWait()
                // Haptic confirms the user-pull completed; the 30 s auto-refresh
                // never routes through here, so the device doesn't buzz unprompted.
                feedback.dataLoad(viewModel.lastRefreshHadError ? .failed : .success)
            },
            makeStopPreview: { stopID in
                AnyView(
                    StopViewControllerPreview(stopID: stopID, application: application)
                        .frame(width: 320, height: 400)
                )
            }
        )
    }

    /// Computed (rebuilt on each body evaluation) to capture current environment and
    /// state values. `coordinator` is an `@EnvironmentObject` and `editingBookmark`,
    /// `isShowingTrackError` are `@State` — none are available in `init()`, and the
    /// latter two must be written through their projected bindings, which exist only
    /// during body evaluation. Rebuilding the handler's eight closures is cheap (stack
    /// allocation), and `BookmarksListView` stores it as a plain `let` without keying
    /// view identity off it, so per-eval rebuilds are safe and correct.
    private var navigationHandler: BookmarksNavigationHandler {
        Self.makeNavigationHandler(
            application: application,
            viewModel: viewModel,
            actions: actions,
            coordinator: coordinator,
            feedback: feedback,
            onEdit: { editingBookmark = $0 },
            onTrackFailure: { isShowingTrackError = true }
        )
    }

    var body: some View {
        NavigationStack {
            BookmarksListView(
                viewModel: viewModel,
                navigation: navigationHandler,
                presentation: .sheet
            )
                .environment(\.obaFormatters, application.formatters)
                .navigationTitle(Text(Strings.bookmarks))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(Strings.close) { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        refreshButton
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        sortMenu
                    }
                }
        }
        .searchSheetBackground()
        .onAppear { viewModel.start() }
        // Stops the 30 s poll when the sheet goes away. The tab does the same on
        // `viewWillDisappear`.
        .onDisappear { viewModel.deactivate() }
        .sheet(item: $editingBookmark) { bookmark in
            BookmarkEditorHost(application: application, bookmark: bookmark) {
                editingBookmark = nil
                viewModel.rebuildSections()
            }
        }
        .alert(
            OBALoc("live_activity.error.title", value: "Unable to Start Tracking", comment: "Alert title when Live Activity fails to start"),
            isPresented: $isShowingTrackError
        ) {
            Button(Strings.ok, role: .cancel) { }
        } message: {
            Text(OBALoc("live_activity.error.message", value: "Please check your Live Activities settings in Settings.", comment: "Alert message for Live Activity error. \"Settings\" is the iOS Settings app."))
        }
    }

    /// Replaces pull-to-refresh, which on a sheet competes with the drag-down
    /// dismiss gesture. Drives the same `navigation.refresh()` closure the tab's
    /// pull gesture does, so the fetch and its completion haptic are identical.
    ///
    /// Tapping swaps the button for a spinner immediately, held for at least
    /// `minimumSpinnerDuration` so even an instant refresh is visibly
    /// acknowledged. The button is gone for the duration, so a second tap can't
    /// stack another batch on the first.
    @ViewBuilder
    private var refreshButton: some View {
        if isRefreshing {
            ProgressView()
        } else {
            Button {
                Task {
                    isRefreshing = true
                    let startedAt = ContinuousClock.now

                    await navigationHandler.refresh()

                    // Pad out the remainder of the floor, if the fetch beat it.
                    let elapsed = ContinuousClock.now - startedAt
                    if elapsed < Self.minimumSpinnerDuration {
                        try? await Task.sleep(for: Self.minimumSpinnerDuration - elapsed)
                    }

                    isRefreshing = false
                }
            } label: {
                Label(Strings.refresh, systemImage: AppSymbol.refresh)
            }
        }
    }

    /// Mirrors the tab's `rebuildSortMenu`, including which item is checked.
    private var sortMenu: some View {
        Menu {
            Picker(Strings.sort, selection: sortSelection) {
                Label(
                    OBALoc("bookmarks_controller.sort_menu.sort_by_group", value: "Sort by Group", comment: "A menu item that allows the user to sort their bookmarks into groups."),
                    systemImage: "folder"
                )
                .tag(true)

                Label(
                    OBALoc("bookmarks_controller.sort_menu.sort_by_distance", value: "Sort by Distance", comment: "A menu item that allows the user to sort their bookmarks by distance from the user."),
                    systemImage: "location.circle"
                )
                .tag(false)
            }
            .pickerStyle(.inline)
        } label: {
            Label(Strings.sort, systemImage: "arrow.up.arrow.down.circle")
        }
    }

    private var sortSelection: Binding<Bool> {
        Binding(
            get: { viewModel.sortByGroup },
            set: { viewModel.updateSortType(byGroup: $0) }
        )
    }
}
