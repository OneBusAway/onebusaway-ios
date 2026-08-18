//
//  BookmarksViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import SwiftUI
import Combine
import OBAKitCore
import WidgetKit
import ActivityKit

/// Hosting shell for the SwiftUI Bookmarks tab. Owns UIKit-side chrome (the
/// Edit bar button and Sort menu), the Live Activity lifecycle, and the modals
/// the tab presents (bookmark editor, manage bookmarks/groups). Everything
/// that leaves the list — row taps, edit/delete/track actions, pull-to-refresh
/// completion feedback — routes here through `BookmarksNavigationHandler`, so
/// the SwiftUI layer stays router-free and holds no `Application` reference.
class BookmarksViewController: UIHostingController<BookmarksRootView>,
    AppContext,
    BookmarkEditorDelegate,
    ManageBookmarksDelegate,
    ModalDelegate {

    let application: Application
    let viewModel: BookmarksViewModel
    private var cancellables = Set<AnyCancellable>()

    private lazy var dataLoadFeedbackGenerator = DataLoadFeedbackGenerator(application: application)
    private lazy var bookmarkActions = BookmarkActions(application: application)

    init(application: Application) {
        self.application = application
        self.viewModel = BookmarksViewModel(application: application)

        // Seed with placeholder closures; `self` isn't available until super.init
        // returns, so the real handler (which captures `self`) is installed below.
        super.init(rootView: BookmarksRootView(
            viewModel: viewModel,
            userDefaults: application.userDefaults,
            navigation: Self.placeholderNavigation,
            formatters: application.formatters
        ))

        rootView.navigation = makeNavigationHandler()

        title = OBALoc("bookmarks_controller.title", value: "Bookmarks", comment: "Title of the Bookmarks tab")
        tabBarItem.image = Icons.bookmarksTabIcon
        tabBarItem.selectedImage = Icons.bookmarksSelectedTabIcon

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: OBALoc("bookmarks_controller.groups_button_title", value: "Edit", comment: "Groups button title in Bookmarks controller"), style: .plain, target: self, action: #selector(manageGroups))
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()
        rebuildSortMenu()
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.start()
        consumePendingLiveActivityShortcut()

        application.notificationCenter.addObserver(self, selector: #selector(applicationEnteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        application.notificationCenter.addObserver(self, selector: #selector(applicationWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        application.notificationCenter.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        application.notificationCenter.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)

        viewModel.deactivate()
    }

    // MARK: - Navigation Handler

    /// A no-op handler used only to satisfy the required `rootView` before
    /// `self` is available; replaced immediately with `makeNavigationHandler()`.
    /// The assertions turn a future regression that ships the placeholder
    /// (e.g. an init reorder) into a loud debug-time trap instead of a
    /// Bookmarks tab where taps silently do nothing.
    private static let placeholderNavigation = BookmarksNavigationHandler(
        selectBookmark: { _ in assertionFailure("placeholder navigation handler invoked") },
        editBookmark: { _ in assertionFailure("placeholder navigation handler invoked") },
        deleteBookmark: { _ in assertionFailure("placeholder navigation handler invoked") },
        trackBookmark: { _ in assertionFailure("placeholder navigation handler invoked") },
        togglePin: { _ in assertionFailure("placeholder navigation handler invoked") },
        liveActivitiesEnabled: {
            assertionFailure("placeholder navigation handler invoked")
            return false
        },
        refresh: { assertionFailure("placeholder navigation handler invoked") },
        makeStopPreview: { _ in
            assertionFailure("placeholder navigation handler invoked")
            return AnyView(EmptyView())
        }
    )

    private func makeNavigationHandler() -> BookmarksNavigationHandler {
        BookmarksNavigationHandler(
            selectBookmark: { [weak self] bookmark in
                guard let self else { return }
                self.application.viewRouter.navigateTo(stop: bookmark.stop, from: self, bookmark: bookmark)
            },
            editBookmark: { [weak self] bookmark in
                guard let self else { return }
                let editor = self.bookmarkActions.makeBookmarkEditor(for: bookmark, delegate: self)
                self.application.viewRouter.present(editor, from: self)
            },
            deleteBookmark: { [weak self] bookmark in
                guard let self else { return }
                self.bookmarkActions.reportDeletion(of: bookmark)
                self.viewModel.deleteBookmark(bookmark)
            },
            trackBookmark: { [weak self] bookmark in
                guard let self else { return }
                let arrivals = self.viewModel.arrivalDepartures(for: bookmark)
                if self.bookmarkActions.startLiveActivity(for: bookmark, arrivalDepartures: arrivals) == .failed {
                    self.showLiveActivityErrorAlert()
                }
            },
            togglePin: { [weak self] bookmark in
                guard let self else { return }
                self.application.userDataStore.setPinned(!bookmark.isPinned, for: bookmark)
            },
            liveActivitiesEnabled: { ActivityAuthorizationInfo().areActivitiesEnabled },
            refresh: { [weak self] in
                guard let self else { return }
                await self.viewModel.refreshAndWait()
                // Haptic confirms the user-pull completed; the 30 s auto-refresh
                // never routes through here, so the device doesn't buzz unprompted.
                // Reflect whether the just-completed batch reported any fetch
                // failure (superseded batches don't count) so a failed pull
                // doesn't buzz success.
                self.dataLoadFeedbackGenerator.dataLoad(self.viewModel.lastRefreshHadError ? .failed : .success)
            },
            makeStopPreview: { [weak self] stopID in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(
                    StopViewControllerPreview(stopID: stopID, application: self.application)
                        .frame(width: 320, height: 400)
                )
            }
        )
    }

    // MARK: - Sorting

    private func rebuildSortMenu() {
        let groupTitle = OBALoc("bookmarks_controller.sort_menu.sort_by_group", value: "Sort by Group", comment: "A menu item that allows the user to sort their bookmarks into groups.")
        let groupSortAction = UIAction(title: groupTitle, image: UIImage(systemName: "folder")) { [weak self] _ in
            self?.viewModel.updateSortType(byGroup: true)
        }

        let distanceTitle = OBALoc("bookmarks_controller.sort_menu.sort_by_distance", value: "Sort by Distance", comment: "A menu item that allows the user to sort their bookmarks by distance from the user.")
        let distanceSortAction = UIAction(title: distanceTitle, image: UIImage(systemName: "location.circle")) { [weak self] _ in
            self?.viewModel.updateSortType(byGroup: false)
        }

        if viewModel.sortByGroup {
            groupSortAction.state = .on
            distanceSortAction.state = .off
        }
        else {
            groupSortAction.state = .off
            distanceSortAction.state = .on
        }

        let sortMenu = UIMenu(title: Strings.sort, options: .displayInline, children: [groupSortAction, distanceSortAction])
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: Strings.sort, image: UIImage(systemName: "arrow.up.arrow.down.circle"), menu: sortMenu)
    }

    // MARK: - Refresh Widget

    /// Pushes freshly-loaded *arrival times* to the widget. Changes to the
    /// bookmark set itself are handled app-wide by `BookmarkWidgetRefresher`,
    /// which observes the store — this tab is not the only surface that edits
    /// bookmarks, so it must not be the only thing that refreshes the widget.
    func reloadWidget() {
        Logger.info("Reloading the widget")
        WidgetCenter.shared.reloadTimelines(ofKind: BookmarkWidgetRefresher.widgetKind)
    }

    // MARK: - Live Activity Management

    /// Starts a Live Activity queued by the Track Bookmark Shortcut (#1222).
    /// Waits until arrivals for that stop have loaded so we reuse the Track
    /// path instead of hitting its empty-data error. Peek until arrivals are
    /// in; clear only when starting or when the request cannot succeed.
    func consumePendingLiveActivityShortcut() {
        guard let id = LiveActivityShortcutRequest.peek(userDefaults: application.userDefaults) else { return }
        guard let bookmark = application.userDataStore.findBookmark(id: id) else {
            _ = LiveActivityShortcutRequest.take(userDefaults: application.userDefaults)
            return
        }

        guard viewModel.hasFetchedArrivals(for: bookmark) else { return }

        _ = LiveActivityShortcutRequest.take(userDefaults: application.userDefaults)
        let arrivals = viewModel.arrivalDepartures(for: bookmark)
        if bookmarkActions.startLiveActivity(for: bookmark, arrivalDepartures: arrivals) == .failed {
            showLiveActivityErrorAlert()
        }
    }

    func updateRunningLiveActivities() {
        let activities = Activity<TripAttributes>.activities
        for activity in activities {
            let staticData = activity.attributes.staticData
            let matchingBookmark = application.userDataStore.bookmarks.first(where: { bookmark in
                // Delegates to the shared identity rule so this match can't
                // drift from the start paths' duplicate guard.
                let keys = BookmarkActions.liveActivityKeys(for: bookmark)
                let bookmarkIdentity = TripAttributes.StaticData(
                    routeShortName: keys.routeShortName,
                    routeHeadsign: keys.routeHeadsign,
                    stopID: bookmark.stopID
                )
                return bookmarkIdentity.tracksSameTrip(as: staticData)
            })
            let arrivalDepartures = matchingBookmark.map { viewModel.arrivalDepartures(for: $0) } ?? []

            if matchingBookmark != nil, let contentState = BookmarkActions.buildContentState(from: arrivalDepartures) {
                // Re-arm the push token/lifecycle observers on relaunch. `startLiveActivity`
                // only tracks activities it creates in-session, so without this a Live Activity
                // that's still running after a relaunch would never re-establish its observers
                // and would never unregister when it later ends. Guarded so repeated calls to
                // updateRunningLiveActivities() don't cancel/rebuild an already-armed task — and
                // because the tracker is app-scoped, the guard also covers an activity started
                // from the stop page, which we must not steal the observers out from under.
                //
                // Deliberately keyed on the token task and not on `isTracking`: an activity that
                // the sweep below could only lifecycle-observe (no matching bookmark at the time)
                // must still be upgradable to a full registration once its bookmark reappears.
                if !application.liveActivityTracker.isForwardingPushToken(activityID: activity.id) {
                    application.liveActivityTracker.track(
                        activity: activity,
                        metadata: .init(arrivalDepartures.first)
                    )
                }
                // Coalesce per activity ID. The worker re-fetches the activity
                // before applying content, so its current relevance score is
                // preserved across the asynchronous hop (#1197).
                let activityID = activity.id
                Task {
                    await LiveActivityUpdateCoalescer.shared.schedule(
                        activityID: activityID,
                        state: contentState
                    )
                }
            } else if !application.liveActivityTracker.isTracking(activityID: activity.id) {
                // No bookmark/arrival data to register push updates with, but the activity is
                // still running (and may have a delete URL persisted from a prior session).
                // Arm just the lifecycle observer so dismiss/end still triggers `unregister`.
                application.liveActivityTracker.observeLifecycle(of: activity)
            }
        }
    }

    // MARK: - Notifications

    @objc private func applicationEnteredBackground(note: Notification) {
        viewModel.deactivate()
    }

    @objc private func applicationWillEnterForeground() {
        viewModel.start()
        consumePendingLiveActivityShortcut()
    }

    // MARK: - Bookmark Groups

    @objc private func manageGroups() {
        let manageGroupsController = ManageBookmarksAndGroupsViewController(application: application, delegate: self)
        let navigation = UINavigationController(rootViewController: manageGroupsController)
        application.viewRouter.present(navigation, from: self)
    }

    // MARK: - BookmarkEditorDelegate

    func bookmarkEditorCancelled(_ viewController: UIViewController) {
        viewController.dismiss(animated: true, completion: nil)
    }

    func bookmarkEditor(_ viewController: UIViewController, editedBookmark bookmark: Bookmark, isNewBookmark: Bool) {
        viewController.dismiss(animated: true, completion: nil)
        viewModel.rebuildSections()
    }

    // MARK: - ModalDelegate

    func dismissModalController(_ controller: UIViewController) {
        controller.dismiss(animated: true, completion: nil)
    }

    // MARK: - ManageBookmarksDelegate

    func manageBookmarksReloadData(_ controller: ManageBookmarksAndGroupsViewController) {
        viewModel.rebuildSections()
    }
}

// MARK: - ViewModel Binding

private extension BookmarksViewController {
    func bindViewModel() {
        // Per-bookmark fetch completions: the view model has already rebuilt
        // its sections; push the fresh data into any running Live Activities.
        viewModel.didUpdate
            .sink { [weak self] _ in
                self?.updateRunningLiveActivities()
                self?.consumePendingLiveActivityShortcut()
            }
            .store(in: &cancellables)

        // Batch-boundary signal: reload the widget timeline once per completed
        // batch rather than once per per-bookmark fetch. (The user-pull haptic
        // lives in the navigation handler's `refresh` closure, which only runs
        // for explicit pulls.)
        viewModel.$isLoading
            .filter { !$0 }
            .sink { [weak self] _ in
                self?.reloadWidget()
            }
            .store(in: &cancellables)

        // Keep the Sort menu's checkmarks in sync with the preference.
        viewModel.$sortByGroup
            .dropFirst()
            .sink { [weak self] _ in
                self?.rebuildSortMenu()
            }
            .store(in: &cancellables)
    }
}

// MARK: - Stop Preview

/// Lazily-built UIKit preview for row long-presses; the stop controller is
/// constructed only when SwiftUI actually presents the context-menu preview.
struct StopViewControllerPreview: UIViewControllerRepresentable {
    let stopID: StopID
    let application: Application

    func makeUIViewController(context: Context) -> UIViewController {
        application.viewRouter.makeStopController(stopID: stopID)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
