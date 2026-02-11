//
//  BookmarksViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Combine
import CoreLocation
import OBAKitCore
import WidgetKit
import ActivityKit

/// The view controller that powers the Bookmarks tab of the app.
@objc(OBABookmarksViewController)
public class BookmarksViewController: UIViewController,
                                      AppContext,
                                      BookmarkEditorDelegate,
                                      ManageBookmarksDelegate,
                                      ModalDelegate,
                                      OBAListViewDataSource,
                                      OBAListViewCollapsibleSectionsDelegate,
                                      OBAListViewContextMenuDelegate {

    let application: Application
    let viewModel: BookmarksViewModel
    private var cancellables = Set<AnyCancellable>()

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
        self.viewModel = BookmarksViewModel(application: application)
        super.init(nibName: nil, bundle: nil)

        title = OBALoc("bookmarks_controller.title", value: "Bookmarks", comment: "Title of the Bookmarks tab")
        tabBarItem.image = Icons.bookmarksTabIcon
        tabBarItem.selectedImage = Icons.bookmarksSelectedTabIcon

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: OBALoc("bookmarks_controller.groups_button_title", value: "Edit", comment: "Groups button title in Bookmarks controller"), style: .plain, target: self, action: #selector(manageGroups))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var sortBookmarksByGroup: Bool {
        get { viewModel.sortByGroup }
        set { viewModel.updateSortType(byGroup: newValue) }
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
        bindViewModel()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.start()

        application.notificationCenter.addObserver(self, selector: #selector(applicationEnteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        application.notificationCenter.addObserver(self, selector: #selector(applicationWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)

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
        application.notificationCenter.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)

        viewModel.deactivate()
    }

    // MARK: - Sorting

    private func rebuildSortMenu() {
        let groupTitle = OBALoc("bookmarks_controller.sort_menu.sort_by_group", value: "Sort by Group", comment: "A menu item that allows the user to sort their bookmarks into groups.")
        let groupSortAction = UIAction(title: groupTitle, image: UIImage(systemName: "folder")) { _ in
            self.sortBookmarksByGroup = true
        }

        let distanceTitle = OBALoc("bookmarks_controller.sort_menu.sort_by_distance", value: "Sort by Distance", comment: "A menu item that allows the user to sort their bookmarks by distance from the user.")
        let distanceSortAction = UIAction(title: distanceTitle, image: UIImage(systemName: "location.circle")) { _ in
            self.sortBookmarksByGroup = false
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

    /// `true` when the user pulled to refresh and the spinner is currently driven by that
    /// gesture. Auto-refreshes (the 30 s timer) leave this `false`, so the refresh control
    /// only animates for explicit user pulls.
    private var isUserRefreshing = false

    @objc private func refreshControlPulled() {
        isUserRefreshing = true
        refreshControl.beginRefreshing()
        viewModel.refresh()
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

        let items = activeBookmarks.compactMap { buildListItem($0) }
        var section = OBAListViewSection(id: id, title: title, contents: items)
        section.configuration = .appearance(.plain)
        return section
    }

    /// Builds a `BookmarkArrivalViewModel` for a single bookmark, loading arrival data if available.
    private func buildListItem(_ bookmark: Bookmark) -> BookmarkArrivalViewModel? {
        // Build arrival/departure pairs if this is a trip bookmark with data.
        var arrDeps: [BookmarkArrivalViewModel.ArrivalDepartureShouldHighlightPair] = []

        if bookmark.isTripBookmark {
            let data = viewModel.arrivalDepartures(for: bookmark)
            arrDeps = data.map { arrDep in
                (arrDep, shouldHighlight(arrivalDeparture: arrDep))
            }
        }

        return BookmarkArrivalViewModel(
            bookmark: bookmark,
            arrivalDepartures: arrDeps,
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
            self.viewModel.deleteBookmark(bookmark)
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

        let menu: OBAListViewMenuActions.MenuProvider = { [weak self] _ -> UIMenu? in
            guard let self else { return nil }

            var children: [UIMenuElement] = []
            // Check if Live Activities are enabled
            if ActivityAuthorizationInfo().areActivitiesEnabled {
                let title = OBALoc("bookmarks_controller.context_menu.track_live_activity", value: "Track", comment: "Action to start a Live Activity for a specific bookmark")
                let liveActivityAction = UIAction(
                    title: title,
                    image: Icons.liveActivity
                ) { [weak self] _ in
                    self?.startLiveActivity(for: item)
                }
                children.append(liveActivityAction)
            }
            children.append(self.editAction(for: item))
            children.append(self.deleteAction(for: item))
            return UIMenu(title: item.name, children: children)
        }

        let previewProvider: OBAListViewMenuActions.PreviewProvider = { () -> UIViewController? in
            let stopVC = self.application.viewRouter.makeStopController(stopID: item.stopID)
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
        // Use structured properties directly from the Bookmark model instead of parsing
        // the display name, which would break on hyphenated route names like "A-Line".
        let routeShortName = viewModel.bookmark.routeShortName ?? viewModel.name
        let routeHeadsign = viewModel.bookmark.tripHeadsign ?? ""

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
            // Note: pushType is set to .token in preparation for future backend support.
            // There is currently no server-side infrastructure to receive push tokens
            // or send APNs updates to Live Activities. When a backend is implemented,
            // add a Task to iterate over activity.pushTokenUpdates and send tokens
            // to the server. That Task must be stored and cancelled in deinit.
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: .token
            )
            Logger.info("Started Live Activity with ID: \(activity.id)")
            showLiveActivityStartedAlert()
        } catch {
            Logger.error("Failed to start Live Activity: \(error)")
            showLiveActivityErrorAlert()
        }
    }

    func updateRunningLiveActivities() {
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
        let statusText = TripBookmarkRow.buildStatusText(from: firstArrival, formatters: formatters)
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

    private func showLiveActivityStartedAlert() {
        let title = OBALoc("live_activity.started.title", value: "Tracking on Lock Screen", comment: "Alert title when a Live Activity starts")
        let message = OBALoc("live_activity.started.message", value: "You'll see live arrival updates on your Lock Screen and Dynamic Island.", comment: "Alert message explaining where to find the Live Activity")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Strings.ok, style: .default))
        present(alert, animated: true)
    }

    private func showLiveActivityErrorAlert() {
        let title = OBALoc("live_activity.error.title", value: "Unable to Start Tracking", comment: "Alert title when Live Activity fails to start")
        let message = OBALoc("live_activity.error.message", value: "Please check your Live Activities settings in System Preferences.", comment: "Alert message for Live Activity error")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Strings.ok, style: .default))
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

    private func bindViewModel() {
        bindListUpdate()
        bindSortPreference()
        bindLoadingState()
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

    // MARK: - ModalDelegate

    public func dismissModalController(_ controller: UIViewController) {
        controller.dismiss(animated: true, completion: nil)
    }

    // MARK: - ManageBookmarksDelegate

    func manageBookmarksReloadData(_ controller: ManageBookmarksAndGroupsViewController) {
        listView.applyData(animated: false)
    }
}

// MARK: - ViewModel Binding

private extension BookmarksViewController {
    func bindListUpdate() {
        // Per-bookmark fetch completions: rebuild the list so each row's arrival
        // times update as soon as that bookmark's data lands.
        viewModel.didUpdate
            .sink { [weak self] _ in
                guard let self else { return }
                listView.applyData(animated: false)
                updateRunningLiveActivities()
            }
            .store(in: &cancellables)
    }

    /// Reacts to the data loader's batch-boundary signal. Ends the user-pull spinner
    /// and fires the once-per-batch side effects (haptic pulse, widget reload) — these
    /// belong here rather than in `didUpdate`, which fires once per per-bookmark fetch
    /// and would multiply the side effects by the bookmark count.
    func bindLoadingState() {
        viewModel.$isLoading
            .filter { !$0 }
            .sink { [weak self] _ in
                guard let self else { return }
                if isUserRefreshing {
                    refreshControl.endRefreshing()
                    // Haptic confirms the user-pull completed; suppress on background
                    // 30 s auto-refreshes so the device doesn't buzz unprompted. Reflect
                    // whether any bookmark fetch in the batch failed so a partial/total
                    // failure doesn't masquerade as a success buzz.
                    dataLoadFeedbackGenerator.dataLoad(viewModel.lastRefreshHadError ? .failed : .success)
                    isUserRefreshing = false
                }
                reloadWidget()
            }
            .store(in: &cancellables)
    }

    func bindSortPreference() {
        viewModel.$sortByGroup
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    listView.applyData(animated: false)
                    rebuildSortMenu()
                }
            }
            .store(in: &cancellables)
    }
}
