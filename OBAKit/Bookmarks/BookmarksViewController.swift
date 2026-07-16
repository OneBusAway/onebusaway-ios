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
            editBookmark: { [weak self] bookmark in self?.editBookmark(bookmark) },
            deleteBookmark: { [weak self] bookmark in self?.deleteBookmark(bookmark) },
            trackBookmark: { [weak self] bookmark in self?.startLiveActivity(for: bookmark) },
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

    func reloadWidget() {
        Logger.info("Reloading the widget")
        WidgetCenter.shared.reloadTimelines(ofKind: "OBAWidget")
    }

    // MARK: - Bookmark Actions

    private func editBookmark(_ bookmark: Bookmark) {
        let bookmarkEditor = EditBookmarkViewController(application: application, stop: bookmark.stop, bookmark: bookmark, delegate: self)
        let navigation = UINavigationController(rootViewController: bookmarkEditor)
        application.viewRouter.present(navigation, from: self)
    }

    private func deleteBookmark(_ bookmark: Bookmark) {
        // Report remove bookmark event to analytics
        if let routeID = bookmark.routeID, let headsign = bookmark.tripHeadsign {
            application.analytics?.reportEvent(
                pageURL: "app://localhost/bookmarks",
                label: AnalyticsLabels.removeBookmark,
                value: AnalyticsLabels.addRemoveBookmarkValue(
                    routeID: routeID,
                    headsign: headsign,
                    stopID: bookmark.stopID))
        }

        viewModel.deleteBookmark(bookmark)
    }

    // MARK: - Live Activity Management

    /// The route name/headsign pair stored in a Live Activity's `StaticData`.
    /// Creation and reconciliation must apply the same fallbacks — comparing
    /// raw optionals against these stored values would never match a bookmark
    /// whose route name or headsign is missing.
    private static func liveActivityKeys(for bookmark: Bookmark) -> (routeShortName: String, routeHeadsign: String) {
        // Use structured properties directly from the Bookmark model instead of parsing
        // the display name, which would break on hyphenated route names like "A-Line".
        (bookmark.routeShortName ?? bookmark.name, bookmark.tripHeadsign ?? "")
    }

    func startLiveActivity(for bookmark: Bookmark) {
        let (routeShortName, routeHeadsign) = Self.liveActivityKeys(for: bookmark)

        let arrivalDepartures = viewModel.arrivalDepartures(for: bookmark)
        let routeColorHex = arrivalDepartures.first?.route.color?.toHex()
        let staticData = TripAttributes.StaticData(
            routeShortName: routeShortName,
            routeHeadsign: routeHeadsign,
            stopID: bookmark.stopID,
            routeColorHex: routeColorHex,
            regionID: application.currentRegion?.regionIdentifier ?? 0
        )

        guard let contentState = buildContentState(from: arrivalDepartures) else {
            // Shouldn't happen — the context menu only offers Track once arrival
            // data has loaded — but if data was cleared between the menu render
            // and the tap, tell the user rather than silently doing nothing.
            Logger.error("Failed to build content state for Live Activity")
            showLiveActivityErrorAlert()
            return
        }

        let attributes = TripAttributes(staticData: staticData)
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: .token
            )
            trackLiveActivity(activity, arrivalDepartures: arrivalDepartures)
            Logger.info("Started Live Activity with ID: \(activity.id)")
            let message = OBALoc("live_activity.started.title", value: "Tracking on Lock Screen", comment: "Toast shown when a Live Activity starts on the Lock Screen")
            ProgressHUD.showSuccessAndDismiss(message: message)
        } catch {
            Logger.error("Failed to start Live Activity: \(error)")
            showLiveActivityErrorAlert()
        }
    }

    func updateRunningLiveActivities() {
        let activities = Activity<TripAttributes>.activities
        for activity in activities {
            let staticData = activity.attributes.staticData
            let matchingBookmark = application.userDataStore.bookmarks.first(where: { bookmark in
                let keys = Self.liveActivityKeys(for: bookmark)
                return bookmark.stopID == staticData.stopID &&
                       keys.routeShortName == staticData.routeShortName &&
                       keys.routeHeadsign == staticData.routeHeadsign
            })
            let arrivalDepartures = matchingBookmark.map { viewModel.arrivalDepartures(for: $0) } ?? []

            if matchingBookmark != nil, let contentState = buildContentState(from: arrivalDepartures) {
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
                    trackLiveActivity(activity, arrivalDepartures: arrivalDepartures)
                }
                // `Activity` is not Sendable and this loop's instance lives in the
                // main-actor region, so it can't be sent to ActivityKit's @concurrent
                // `update`. Re-fetch by ID inside a detached task instead — that copy
                // never crosses an isolation boundary.
                let activityID = activity.id
                Task.detached {
                    guard let activity = Activity<TripAttributes>.activities.first(where: { $0.id == activityID }) else {
                        // The activity ended between the loop and this task; dropping
                        // the update is correct, but log it so a stale Lock Screen is
                        // diagnosable.
                        Logger.info("Live Activity \(activityID) is no longer running; skipping update.")
                        return
                    }
                    await activity.update(
                        .init(state: contentState, staleDate: nil)
                    )
                    Logger.info("Updated Live Activity for stop: \(staticData.stopID) route: \(staticData.routeShortName)")
                }
            } else if !application.liveActivityTracker.isTracking(activityID: activity.id) {
                // No bookmark/arrival data to register push updates with, but the activity is
                // still running (and may have a delete URL persisted from a prior session).
                // Arm just the lifecycle observer so dismiss/end still triggers `unregister`.
                application.liveActivityTracker.observeLifecycle(of: activity)
            }
        }
    }

    // MARK: - Live Activity Helper Methods

    private func buildContentState(from arrivalDepartures: [ArrivalDeparture]) -> TripAttributes.ContentState? {
        guard !arrivalDepartures.isEmpty else {
            return nil
        }
        let arrivals = arrivalDepartures.prefix(3).map { arrDep in
            TripAttributes.ContentState.ArrivalInfo(
                departureTime: Int(arrDep.arrivalDepartureDate.timeIntervalSince1970),
                scheduleStatus: .init(arrDep.scheduleStatus),
                scheduleDeviation: arrDep.deviationFromScheduleInMinutes * 60,
                isArrival: arrDep.arrivalDepartureStatus == .arriving
            )
        }
        return TripAttributes.ContentState(arrivals: Array(arrivals))
    }

    // MARK: - Live Activity Push Registration

    /// Hands `activity` to the app-scoped tracker, which owns the push-token and lifecycle
    /// observers. They deliberately outlive this controller — and every other screen — so that an
    /// activity is unregistered when it actually ends rather than when a view controller happens
    /// to be deallocated. See `LiveActivityTracker`.
    private func trackLiveActivity(_ activity: Activity<TripAttributes>, arrivalDepartures: [ArrivalDeparture]) {
        application.liveActivityTracker.track(
            activity: activity,
            metadata: .init(arrivalDepartures.first)
        )
    }

    // MARK: - Notifications

    @objc private func applicationEnteredBackground(note: Notification) {
        viewModel.deactivate()
    }

    @objc private func applicationWillEnterForeground() {
        viewModel.start()
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
