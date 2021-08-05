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

    let listView = OBAListView()

    public init(application: Application) {
        self.application = application
        super.init(nibName: nil, bundle: nil)

        title = OBALoc("bookmarks_controller.title", value: "Bookmarks", comment: "Title of the Bookmarks tab")
        tabBarItem.image = Icons.bookmarksTabIcon
        tabBarItem.selectedImage = Icons.bookmarksSelectedTabIcon

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: OBALoc("bookmarks_controller.groups_button_title", value: "Edit", comment: "Groups button title in Bookmarks controller"), style: .plain, target: self, action: #selector(manageGroups))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        dataLoader.cancelUpdates()
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

    // MARK: - Refresh Control

    @objc private func refreshControlPulled() {
        dataLoader.loadData()
        refreshControl.beginRefreshing()

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
        var sections = application.userDataStore.bookmarkGroups.compactMap { listSection(group: $0, title: $0.name) }

        // Add grouped bookmarks
        let ungroupedTitle = sections.count > 0 ? OBALoc("bookmarks_controller.ungrouped_bookmarks_section.title", value: "Bookmarks", comment: "The title for the bookmarks controller section that shows bookmarks that aren't in a group.") : nil

        // Add ungrouped bookmarks
        if let section = listSection(group: nil, title: ungroupedTitle) {
            sections.append(section)
        }

        return sections
    }

    private func listSection(group: BookmarkGroup?, title: String?) -> OBAListViewSection? {
        let bookmarks = application.userDataStore.bookmarksInGroup(group)

        let arrivalData = bookmarks
            .filter { $0.regionIdentifier == application.regionsService.currentRegion?.id }
            .compactMap { bookmark -> BookmarkArrivalViewModel? in
            var arrDeps: [BookmarkArrivalViewModel.ArrivalDepartureShouldHighlightPair] = []

            if let key = TripBookmarkKey(bookmark: bookmark) {
                let data = dataLoader.dataForKey(key)
                arrDeps = data.map { arrDep -> BookmarkArrivalViewModel.ArrivalDepartureShouldHighlightPair in
                    return (arrDep, shouldHighlight(arrivalDeparture: arrDep))
                }
            }

            let viewModel = BookmarkArrivalViewModel(bookmark: bookmark, arrivalDepartures: arrDeps, onSelect: onSelectBookmark)
            return viewModel
        }

        guard arrivalData.count > 0 else { return nil }

        let groupID: String = group?.id.uuidString ?? "unknown_group"
        let groupName = group?.name ?? OBALoc("bookmarks_controller.ungrouped_bookmarks_section.title", value: "Bookmarks", comment: "The title for the bookmarks controller section that shows bookmarks that aren't in a group.")

        var section = OBAListViewSection(id: groupID, title: groupName, contents: arrivalData)
        section.configuration = .appearance(.plain)
        return section
    }

    public func emptyData(for listView: OBAListView) -> OBAListView.EmptyData? {
        let body = application.hasDataToMigrate ?
            Strings.emptyBookmarkBodyWithPendingMigration :
            Strings.emptyBookmarkBody

        return .standard(.init(title: Strings.emptyBookmarkTitle, body: body))
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
                self.application.analytics?.reportEvent?(
                    .userAction,
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

    var currentPreviewingViewController: UIViewController?
    public func contextMenu(_ listView: OBAListView, for item: AnyOBAListViewItem) -> OBAListViewMenuActions? {
        guard let item = item.as(BookmarkArrivalViewModel.self) else { return nil }

        let menu: OBAListViewMenuActions.MenuProvider = { _ -> UIMenu? in
            let children: [UIMenuElement] = [self.editAction(for: item), self.deleteAction(for: item)]
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

        return OBAListViewMenuActions(previewProvider: previewProvider,
                               performPreviewAction: commitPreviewAction,
                               contextMenuProvider: menu)
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
