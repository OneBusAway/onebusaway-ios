//
//  BookmarksViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import CoreLocation
import OBAKitCore
import WidgetKit
import ActivityKit

/// The view controller that powers the Bookmarks tab of the app.
@objc(OBABookmarksViewController)
public class BookmarksViewController: UIViewController,
                                      AppContext,
                                      BookmarkEditorDelegate,
                                      BookmarkDataDelegate,
                                      ManageBookmarksDelegate,
                                      ModalDelegate,
                                      OBAListViewDataSource,
                                      OBAListViewCollapsibleSectionsDelegate,
                                      OBAListViewContextMenuDelegate {

    let application: Application

    // TODO: property wrapper??
    public var collapsedSections: Set<OBAListViewSection.ID> {
        get {
            var sections: Set<OBAListViewSection.ID>?
            do {
                try sections = application.userDefaults.decodeUserDefaultsObjects(
                    type: Set<OBAListViewSection.ID>.self,
                    key: "collapsedBookmarkSections") ?? []
            } catch let error {
                Logger.error("Unable to decode toggledSections: \(error)")
            }
            return sections ?? []
        } set {
            do {
                try application.userDefaults.encodeUserDefaultsObjects(newValue, key: "collapsedBookmarkSections")
            } catch let error {
                Logger.error("Unable to decode toggledSections: \(error)")
            }
        }
    }

    public var selectionFeedbackGenerator: UISelectionFeedbackGenerator? = UISelectionFeedbackGenerator()
    fileprivate lazy var dataLoadFeedbackGenerator = DataLoadFeedbackGenerator(application: application)

    let listView = OBAListView()

    public init(application: Application) {
        self.application = application
        super.init(nibName: nil, bundle: nil)

        title = OBALoc("bookmarks_controller.title", value: "Bookmarks", comment: "Title of the Bookmarks tab")
        tabBarItem.image = Icons.bookmarksTabIcon
        tabBarItem.selectedImage = Icons.bookmarksSelectedTabIcon

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: OBALoc("bookmarks_controller.groups_button_title", value: "Edit", comment: "Groups button title in Bookmarks controller"), style: .plain, target: self, action: #selector(manageGroups))

        application.userDefaults.register(defaults: [
            userDefaultsKeys.sortBookmarksByGroup.rawValue: true
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        dataLoader.cancelUpdates()
    }

    // MARK: - User Defaults

    private enum userDefaultsKeys: String {
        case sortBookmarksByGroup = "OBABookmarksController_SortBookmarksByGroup"
    }

    private var sortBookmarksByGroup: Bool {
        get {
            application.userDefaults.bool(forKey: userDefaultsKeys.sortBookmarksByGroup.rawValue)
        }
        set {
            application.userDefaults.setValue(newValue, forKey: userDefaultsKeys.sortBookmarksByGroup.rawValue)
            listView.applyData(animated: false)
        }
    }

    // MARK: - UIViewController
    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground
        listView.obaDataSource = self
        listView.collapsibleSectionsDelegate = self
        listView.contextMenuDelegate = self
        listView.formatters = application.formatters
        listView.register(listViewItem: BookmarkArrivalViewModel.self)
        view.addSubview(listView)
        listView.pinToSuperview(.edges)

        rebuildSortMenu()

        dataLoader.loadData()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        application.notificationCenter.addObserver(self, selector: #selector(applicationEnteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)

        if application.userDataStore.bookmarks.count == 0 {
            refreshControl.removeFromSuperview()
        } else {
            listView.addSubview(refreshControl)
        }

        listView.applyData(animated: false)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        application.notificationCenter.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)

        dataLoader.cancelUpdates()
    }

    // MARK: - Sorting

    private func rebuildSortMenu() {
        let groupTitle = OBALoc("bookmarks_controller.sort_menu.sort_by_group", value: "Sort by Group", comment: "A menu item that allows the user to sort their bookmarks into groups.")
        let groupSortAction = UIAction(title: groupTitle, image: UIImage(systemName: "folder")) { _ in
            self.sortBookmarksByGroup = true
            self.rebuildSortMenu()
        }

        let distanceTitle = OBALoc("bookmarks_controller.sort_menu.sort_by_distance", value: "Sort by Distance", comment: "A menu item that allows the user to sort their bookmarks by distance from the user.")
        let distanceSortAction = UIAction(title: distanceTitle, image: UIImage(systemName: "location.circle")) { _ in
            self.sortBookmarksByGroup = false
            self.rebuildSortMenu()
        }

        if self.sortBookmarksByGroup {
            groupSortAction.state = .on
            distanceSortAction.state = .off
        }
        else {
            groupSortAction.state = .off
            distanceSortAction.state = .on
        }

        let sortMenu = UIMenu(title: Strings.sort, options: .displayInline, children: [groupSortAction, distanceSortAction])
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "MORE", image: UIImage(systemName: "arrow.up.arrow.down.circle"), menu: sortMenu)
    }

    // MARK: Refresh Widget
    func reloadWidget() {
        Logger.info("Reloading the widget")
        WidgetCenter.shared.reloadTimelines(ofKind: "OBAWidget")
    }

    // MARK: - Refresh Control

    @objc private func refreshControlPulled() {
        dataLoader.loadData()
        refreshControl.beginRefreshing()
        reloadWidget()

        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.refreshControl.endRefreshing()
        }
    }

    private lazy var refreshControl: UIRefreshControl = {
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(refreshControlPulled), for: .valueChanged)
        return refresh
    }()

    // MARK: - List view
    public func items(for listView: OBAListView) -> [OBAListViewSection] {
        if sortBookmarksByGroup {
            return listItemsSortedByGroup()
        }
        else if application.locationService.currentLocation == nil {
            return listItemsSortedByGroup()
        }
        else {
            return listItemsSortedByDistance()
        }
    }
    /// Creates an `OBAListViewSection` containing the specified bookmarks.
    /// - Parameters:
    ///   - bookmarks: The list of `Bookmark`s to include in this section.
    ///   - id: The unique ID of the section. Used for diffing.
    ///   - title: The section header title.
    private func buildListSection(bookmarks: [Bookmark], id: String, title: String) -> OBAListViewSection? {
        let currentRegionID = application.regionsService.currentRegion?.id
        let activeBookmarks = bookmarks.filter { $0.regionIdentifier == currentRegionID }

        guard !activeBookmarks.isEmpty else { return nil }

        let items = activeBookmarks.map {
            buildListItem($0)
        }.compactMap({$0})

        return OBAListViewSection(id: id, title: title, contents: items)
    }

    private func buildListItem(_ bookmark: Bookmark) -> BookmarkArrivalViewModel? {
        guard bookmark.isTripBookmark,
              let routeID = bookmark.routeID,
              let routeShortName = bookmark.routeShortName,
              let tripHeadsign = bookmark.tripHeadsign else {
            return BookmarkArrivalViewModel(
                bookmark: bookmark,
                arrivalDepartures: [],
                onSelect: { [weak self] viewModel in
                    self?.onSelectBookmark(viewModel)
                }
            )
        }
        let tripBookmarkKey = TripBookmarkKey(
            stopID: bookmark.stopID,
            routeShortName: routeShortName,
            routeID: routeID,
            tripHeadsign: tripHeadsign
        )
        let arrivalDepartures = dataLoader.dataForKey(tripBookmarkKey)
        guard !arrivalDepartures.isEmpty else {
            return BookmarkArrivalViewModel(
                bookmark: bookmark,
                arrivalDepartures: [],
                onSelect: { [weak self] viewModel in
                    self?.onSelectBookmark(viewModel)
                }
            )
        }
        // Track highlight status - create the pairs array
        let arrivalPairs: [BookmarkArrivalViewModel.ArrivalDepartureShouldHighlightPair] = arrivalDepartures.map {
            (arrDep: $0, shouldHighlightOnDisplay: shouldHighlight(arrivalDeparture: $0))
        }

        return BookmarkArrivalViewModel(
            bookmark: bookmark,
            arrivalDepartures: arrivalPairs,
            onSelect: { [weak self] viewModel in
                self?.onSelectBookmark(viewModel)
            }
        )
    }

    public func emptyData(for listView: OBAListView) -> OBAListView.EmptyData? {
        var title: String
        var body: String

        if application.hasDataToMigrate {
            title = Strings.emptyBookmarkTitle
            body = Strings.emptyBookmarkBodyWithPendingMigration
        }
        else if application.userDataStore.bookmarks.isEmpty {
            title = Strings.emptyBookmarkTitle
            body = Strings.emptyBookmarkBody
        }
        else {
            return nil
        }
        return .standard(.init(title: title, body: body))
    }

    // MARK: - Group Sort

    private func listItemsSortedByGroup() -> [OBAListViewSection] {
        // Add grouped bookmarks
        var sections = application.userDataStore.bookmarkGroups.compactMap { buildListSection(group: $0) }

        // Add ungrouped bookmarks
        if let section = buildListSection(group: nil) {
            sections.append(section)
        }

        return sections
    }

    /// Creates an `OBAListViewSection` containing the specified bookmark group's contents.
    /// - Parameter group: The bookmark group to turn into an `OBAListViewSection`
    private func buildListSection(group: BookmarkGroup?) -> OBAListViewSection? {
        return buildListSection(
            bookmarks: application.userDataStore.bookmarksInGroup(group),
            id: group?.id.uuidString ?? "unknown_group",
            title: group?.name ?? OBALoc("bookmarks_controller.ungrouped_bookmarks_section.title", value: "Bookmarks", comment: "The title for the bookmarks controller section that shows bookmarks that aren't in a group.")
        )
    }

    // MARK: - Distance Sort

    /// Provides a way to check if the user wants to sort by distance, but cannot for whatever reason right now.
    private var distanceSortRequestedButUnavailable: Bool {
        !sortBookmarksByGroup && application.locationService.currentLocation == nil
    }

    /// Builds a single item array that contains a list of all bookmarks in the current region sorted by distance from the current user.
    private func listItemsSortedByDistance() -> [OBAListViewSection] {
        guard let currentLocation = application.locationService.currentLocation else {
            return listItemsSortedByGroup()
        }

        let bookmarks = application.userDataStore.bookmarks.sorted(by: {
            $0.stop.location.distance(from: currentLocation) < $1.stop.location.distance(from: currentLocation)
        })

        return [buildListSection(
            bookmarks: bookmarks,
            id: "distance_sorted_group",
            title: OBALoc("bookmarks_controller.sorted_by_distance_header", value: "Sorted by Distance", comment: "The table section header on the bookmarks controller for when bookmarks are sorted by distance.")
        )].compactMap({$0})
    }

    // MARK: - Bookmark Actions
    private func onSelectBookmark(_ viewModel: BookmarkArrivalViewModel) {
        application.viewRouter.navigateTo(stop: viewModel.bookmark.stop, from: self, bookmark: viewModel.bookmark)
    }

    private func deleteAction(for viewModel: BookmarkArrivalViewModel) -> UIMenu {
        let bookmark = viewModel.bookmark
        let title = OBALoc("bookmarks_controller.delete_bookmark.actionsheet.title", value: "Delete Bookmark", comment: "The title to display to confirm the user's action to delete a bookmark.")

        let deleteConfirmation = UIAction(title: Strings.confirmDelete, image: Icons.delete, attributes: .destructive) { _ in
            // Report remove bookmark event to analytics
            if let routeID = bookmark.routeID, let headsign = bookmark.tripHeadsign {
                self.application.analytics?.reportEvent(
                    pageURL: "app://localhost/bookmarks",
                    label: AnalyticsLabels.removeBookmark,
                    value: AnalyticsLabels.addRemoveBookmarkValue(
                        routeID: routeID,
                        headsign: headsign,
                        stopID: bookmark.stopID))
            }

            // Delete bookmark
            self.application.userDataStore.delete(bookmark: bookmark)
            self.listView.applyData(animated: true)
        }

        return UIMenu(title: title, image: Icons.delete, options: .destructive, children: [deleteConfirmation])
    }

    private func editAction(for viewModel: BookmarkArrivalViewModel) -> UIAction {
        return UIAction(title: Strings.edit, image: UIImage(systemName: "square.and.pencil")) { _ in
            let bookmark = viewModel.bookmark
            let bookmarkEditor = EditBookmarkViewController(application: self.application, stop: bookmark.stop, bookmark: bookmark, delegate: self)
            let navigation = UINavigationController(rootViewController: bookmarkEditor)
            self.application.viewRouter.present(navigation, from: self)
        }
    }

    // MARK: - Context Menu with Live Activity Support

    var currentPreviewingViewController: UIViewController?

    // MARK: - Context Menu
    public func contextMenu(_ listView: OBAListView, for item: AnyOBAListViewItem) -> OBAListViewMenuActions? {
        guard let item = item.as(BookmarkArrivalViewModel.self) else { return nil }

        let menu: OBAListViewMenuActions.MenuProvider = { _ -> UIMenu? in
            var children: [UIMenuElement] = []
            // Check if Live Activities are enabled
            if ActivityAuthorizationInfo().areActivitiesEnabled {
                let title = OBALoc("bookmarks_controller.context_menu.track_live_activity", value: "Track", comment: "Action to start a Live Activity for a specific bookmark")
                let liveActivityAction = UIAction(
                    title: title,
                    image: Icons.liveActivity
                ) { _ in
                    self.startLiveActivity(for: item)
                }
                children.append(liveActivityAction)
            }
            children.append(self.editAction(for: item))
            children.append(self.deleteAction(for: item))
            return UIMenu(title: item.name, children: children)
        }

        let previewProvider: OBAListViewMenuActions.PreviewProvider = { () -> UIViewController? in
            let stopVC = StopViewController(application: self.application, stopID: item.stopID)
            self.currentPreviewingViewController = stopVC
            return stopVC
        }

        let commitPreviewAction: VoidBlock = {
            guard let vc = self.currentPreviewingViewController else { return }
            self.application.viewRouter.navigate(to: vc, from: self)
        }

        return OBAListViewMenuActions(
            previewProvider: previewProvider,
            performPreviewAction: commitPreviewAction,
            contextMenuProvider: menu
        )
    }

    // MARK: - Live Activity Management

    func startLiveActivity(for viewModel: BookmarkArrivalViewModel) {
        let (routeShortName, routeHeadsign) = BookmarkNameParser.parse(viewModel.name)
        let staticData = TripAttributes.StaticData(
            routeShortName: routeShortName,
            routeHeadsign: routeHeadsign,
            stopID: viewModel.stopID
        )
        guard let contentState = buildContentState(for: viewModel) else {
            Logger.error("Failed to build content state for Live Activity")
            return
        }
        let attributes = TripAttributes(staticData: staticData)
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: .token
            )
            Logger.info("Started Live Activity with ID: \(activity.id)")
            trackActivity(activity, for: viewModel.bookmark)
            Task {
                for await pushToken in activity.pushTokenUpdates {
                    let tokenString = pushToken.map { String(format: "%02x", $0) }.joined()
                    Logger.info("Live Activity push token: \(tokenString)")
                    // TODO: Send push token to backend server for APNs updates
                    // Required parameters:
                    // - token: tokenString (for APNs)
                    // - activityID: activity.id (to identify which Live Activity to update)
                    // - stopID: staticData.stopID
                    // - routeShortName: staticData.routeShortName
                    // - routeHeadsign: staticData.routeHeadsign
                    //
                }
            }
            showLiveActivityStartedAlert()
        } catch {
            Logger.error("Failed to start Live Activity: \(error)")
            showLiveActivityErrorAlert()
        }
    }

    func updateRunningLiveActivities() {
            // Get all running activities
        let activities = Activity<TripAttributes>.activities
        for activity in activities {
            let staticData = activity.attributes.staticData
            if let bookmark = application.userDataStore.bookmarks.first(where: { bookmark in
                return bookmark.stopID == staticData.stopID &&
                       bookmark.routeShortName == staticData.routeShortName &&
                       bookmark.tripHeadsign == staticData.routeHeadsign
            }),
                let viewModel = buildListItem(bookmark),
                let contentState = buildContentState(for: viewModel) {
                Task {
                    await activity.update(
                        .init(state: contentState, staleDate: nil)
                    )
                    Logger.info("Updated Live Activity for stop: \(staticData.stopID) route: \(staticData.routeShortName)")
                }
            }
        }
    }

    // MARK: - Live Activity Helper Methods

    private func buildContentState(for viewModel: BookmarkArrivalViewModel) -> TripAttributes.ContentState? {
        guard let arrivalDepartures = viewModel.arrivalDepartures,
              !arrivalDepartures.isEmpty else {
            return nil
        }
        let formatters = application.formatters
        let firstArrival = arrivalDepartures[0]
        let statusText = buildStatusText(from: firstArrival, formatters: formatters)
        let statusColor = formatters.colorForScheduleStatus(firstArrival.scheduleStatus)
        let minutes = arrivalDepartures.prefix(3).map { arrivalDeparture -> TripAttributes.MinuteInfo in
            let minuteText = formatters.shortFormattedTime(until: arrivalDeparture)
            let color = formatters.colorForScheduleStatus(arrivalDeparture.scheduleStatus)
            return TripAttributes.MinuteInfo(text: minuteText, color: color)
        }
        let shouldHighlight = !viewModel.arrivalDeparturesPair.isEmpty &&
                            viewModel.arrivalDeparturesPair[0].shouldHighlightOnDisplay
        return TripAttributes.ContentState(
            statusText: statusText,
            statusColor: statusColor,
            minutes: Array(minutes),
            shouldHighlight: shouldHighlight
        )
    }

    private func buildStatusText(from arrivalDeparture: ArrivalDeparture, formatters: Formatters) -> String {
        let timeString = formatters.timeFormatter.string(from: arrivalDeparture.arrivalDepartureDate)
        let deviationText: String
        if arrivalDeparture.scheduleStatus == .unknown {
            deviationText = Strings.scheduledNotRealTime
        } else {
            deviationText = formatters.formattedScheduleDeviation(for: arrivalDeparture)
        }
        return "\(timeString) - \(deviationText)"
    }

    private func trackActivity(_ activity: Activity<TripAttributes>, for bookmark: Bookmark) {
        var activeActivities = UserDefaults.standard.dictionary(forKey: "activeActivities") as? [String: String] ?? [:]
        activeActivities[bookmark.id.uuidString] = activity.id
        UserDefaults.standard.set(activeActivities, forKey: "activeActivities")
    }

    private func showLiveActivityStartedAlert() {
        let title = OBALoc("live_activity.started.title", value: "Tracking on Lock Screen", comment: "Alert title when a Live Activity starts")
        let message = OBALoc("live_activity.started.message", value: "You'll see live arrival updates on your Lock Screen and Dynamic Island.", comment: "Alert message explaining where to find the Live Activity")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Strings.ok, style: .default)) // Use Strings.ok
        present(alert, animated: true)
    }

    private func showLiveActivityErrorAlert() {
        let title = OBALoc("live_activity.error.title", value: "Unable to Start Tracking", comment: "Alert title when Live Activity fails to start")
        let message = OBALoc("live_activity.error.message", value: "Please check your Live Activities settings in System Preferences.", comment: "Alert message for Live Activity error")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Strings.ok, style: .default)) // Use Strings.ok
        present(alert, animated: true)
    }

    // MARK: - Arrival departure highlight updates
    private var arrivalDepartureTimes = ArrivalDepartureTimes()

    /// Used to determine if the highlight change label in the `ArrivalDeparture`'s collection cell should 'flash' when next rendered.
    ///
    /// This is used to indicate whether the departure time for the `ArrivalDeparture` object has changed.
    ///
    /// - Parameter arrivalDeparture: The ArrivalDeparture object
    /// - Returns: Whether or not to highlight the ArrivalDeparture in its cell.
    private func shouldHighlight(arrivalDeparture: ArrivalDeparture) -> Bool {
        var highlight = false
        if let lastMinutes = arrivalDepartureTimes[arrivalDeparture.tripID] {
            highlight = lastMinutes != arrivalDeparture.arrivalDepartureMinutes
        }

        arrivalDepartureTimes[arrivalDeparture.tripID] = arrivalDeparture.arrivalDepartureMinutes

        return highlight
    }

    // MARK: - BookmarkEditorDelegate

    func bookmarkEditorCancelled(_ viewController: UIViewController) {
        viewController.dismiss(animated: true, completion: nil)
    }

    func bookmarkEditor(_ viewController: UIViewController, editedBookmark bookmark: Bookmark, isNewBookmark: Bool) {
        viewController.dismiss(animated: true, completion: nil)
        listView.applyData(animated: false)
    }

    // MARK: - Data Loading

    private lazy var dataLoader = BookmarkDataLoader(application: application, delegate: self)

    public func dataLoaderDidUpdate(_ dataLoader: BookmarkDataLoader) {
        listView.applyData(animated: false)
        updateRunningLiveActivities()
        dataLoadFeedbackGenerator.dataLoad(.success)
    }

    // MARK: - Notifications

    @objc private func applicationEnteredBackground(note: Notification) {
        dataLoader.cancelUpdates()
    }

    // MARK: - Bookmark Groups

    @objc private func manageGroups() {
        let manageGroupsController = ManageBookmarksAndGroupsViewController(application: application, delegate: self)
        let navigation = UINavigationController(rootViewController: manageGroupsController)
        application.viewRouter.present(navigation, from: self)
    }

    // MARK: - ModalDelegate

    public func dismissModalController(_ controller: UIViewController) {
        controller.dismiss(animated: true, completion: nil)
    }

    // MARK: - ManageBookmarksDelegate

    func manageBookmarksReloadData(_ controller: ManageBookmarksAndGroupsViewController) {
        listView.applyData(animated: false)
    }
}
