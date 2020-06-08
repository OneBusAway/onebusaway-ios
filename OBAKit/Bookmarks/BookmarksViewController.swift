//
//  BookmarksViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/26/19.
//

import UIKit
import IGListKit
import CoreLocation
import OBAKitCore
import CocoaLumberjackSwift

/// The view controller that powers the Bookmarks tab of the app.
@objc(OBABookmarksViewController)
public class BookmarksViewController: UIViewController,
    AppContext,
    BookmarkEditorDelegate,
    BookmarkDataDelegate,
    ListAdapterDataSource,
    ManageBookmarksDelegate,
    ModalDelegate {

    let application: Application

    public init(application: Application) {
        self.application = application
        super.init(nibName: nil, bundle: nil)

        title = OBALoc("bookmarks_controller.title", value: "Bookmarks", comment: "Title of the Bookmarks tab")
        tabBarItem.image = Icons.bookmarksTabIcon

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
        addChildController(collectionController)
        collectionController.view.pinToSuperview(.edges)

        dataLoader.loadData()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        application.notificationCenter.addObserver(self, selector: #selector(applicationEnteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)

        if application.userDataStore.bookmarks.count == 0 {
            refreshControl.removeFromSuperview()
        }
        else {
            collectionController.collectionView.addSubview(refreshControl)
        }

        collectionController.reload(animated: false)
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

    // MARK: - IGListKit

    public lazy var collectionController = CollectionController(application: application, dataSource: self)

    public func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        // Add grouped bookmarks
        var sections = application.userDataStore.bookmarkGroups.compactMap { tableSection(group: $0, title: $0.name) }

        // Add ungrouped bookmarks
        let ungroupedTitle = sections.count > 0 ? OBALoc("bookmarks_controller.ungrouped_bookmarks_section.title", value: "Bookmarks", comment: "The title for the bookmarks controller section that shows bookmarks that aren't in a group.") : nil

        if let section = tableSection(group: nil, title: ungroupedTitle) {
            sections.append(section)
        }

        return sections
    }

    /// Builds a table section from a `BookmarkGroup` or from the ungrouped `Bookmark`s.
    /// - Parameters:
    ///   - group: The bookmark group from which to construct the list of `Bookmark`s. Pass in `nil` to choose ungrouped `Bookmark`s.
    ///   - title: The title that is displayed to the user in the section header. This is optional because ungrouped bookmarks should only have a title if other sections exist.
    private func tableSection(group: BookmarkGroup?, title: String?) -> BookmarkSectionData? {
        let bookmarks = application.userDataStore.bookmarksInGroup(group)

        let arrivalData = bookmarks.compactMap { bm -> BookmarkArrivalData? in
            var arrDeps = [ArrivalDeparture]()

            if let key = TripBookmarkKey(bookmark: bm) {
                arrDeps = dataLoader.dataForKey(key)
            }

            let viewModel = BookmarkArrivalData(bookmark: bm, arrivalDepartures: arrDeps, selected: didSelectBookmark(_:), deleted: didDeleteBookmark(_:), edited: didEditBookmark(_:))
            viewModel.previewDestination = { StopViewController(application: self.application, stop: bm.stop) }

            return viewModel
        }

        if arrivalData.count == 0 {
            return nil
        }

        let toggled: BookmarkSectionToggled = { [weak self] (section, state) in
            guard let self = self else { return }
            self.toggledSections[self.toggledSectionKey(group: section.group)] = state
            self.collectionController.reload(animated: true)
        }

        let sectionData = BookmarkSectionData(group: group, title: title, bookmarkArrivalData: arrivalData, toggled: toggled)
        sectionData.state = toggleState(for: sectionData.group)

        return sectionData
    }

    public func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
        let sectionController = defaultSectionController(for: object)
        return sectionController
    }

    public func emptyView(for listAdapter: ListAdapter) -> UIView? {
        let emptyView = EmptyDataSetView()
        emptyView.titleLabel.text = Strings.emptyBookmarkTitle
        emptyView.bodyLabel.text = Strings.emptyBookmarkBody
        return emptyView
    }

    // MARK: - Bookmark Actions

    private func didSelectBookmark(_ bookmark: Bookmark) {
        application.viewRouter.navigateTo(stop: bookmark.stop, from: self, bookmark: bookmark)
    }

    private func didDeleteBookmark(_ bookmark: Bookmark) {
        let title = OBALoc("bookmarks_controller.delete_bookmark.actionsheet.title", value: "Delete Bookmark", comment: "The title to display to confirm the user's action to delete a bookmark.")
        let message = OBALoc("bookmarks_controller.delete_bookmark.actionsheet.message", value: "Are you sure you want to delete %@?", comment: "The message to display to confirm the user's action to delete a bookmark, includes a placeholder to display the bookmark's name.")
        let formattedMessage = String(format: message, bookmark.name)

        let alert = UIAlertController(title: title,
                                      message: formattedMessage,
                                      preferredStyle: .actionSheet)

        alert.addAction(title: Strings.delete, style: .destructive) { [weak self] _ in
            // Report remove bookmark event to analytics
            if let routeID = bookmark.routeID, let headsign = bookmark.tripHeadsign {
                self?.application.analytics?.reportEvent?(.userAction, label: AnalyticsLabels.removeBookmark, value: AnalyticsLabels.addRemoveBookmarkValue(routeID: routeID, headsign: headsign, stopID: bookmark.stopID))
            }

            // Delete bookmark
            self?.application.userDataStore.delete(bookmark: bookmark)
            self?.collectionController.reload(animated: true)
        }
        alert.addAction(title: Strings.cancel, style: .cancel, handler: nil)

        self.present(alert, animated: true)
    }

    private func didEditBookmark(_ bookmark: Bookmark) {
        let bookmarkEditor = EditBookmarkViewController(application: application, stop: bookmark.stop, bookmark: bookmark, delegate: self)
        let navigation = UINavigationController(rootViewController: bookmarkEditor)
        application.viewRouter.present(navigation, from: self)
    }

    // MARK: - Section Toggle State

    /// Creates a key for uniquely identifying a bookmark section when toggling. Necessary because ungrouped bookmarks do not have a group UUID.
    /// - Parameter group: The optional bookmark group, or ungrouped bookmarks, for which a key will be determined.
    private func toggledSectionKey(group: BookmarkGroup?) -> String {
        group?.id.uuidString ?? "ungrouped"
    }

    /// Whether the specified section should be open or closed.
    /// - Parameter group: The optional bookmark group, or ungrouped bookmarks.
    private func toggleState(for group: BookmarkGroup?) -> BookmarkSectionState {
        let key = toggledSectionKey(group: group)
        return toggledSections[key] ?? .open
    }

    /// A store of toggled sections.
    private var toggledSections: [String: BookmarkSectionState] {
        get {
            var sections = [String: BookmarkSectionState]()
            do {
                try sections = application.userDefaults.decodeUserDefaultsObjects(type: [String: BookmarkSectionState].self, key: "toggledBookmarkSections") ?? [:]
            } catch let error {
                DDLogError("Unable to decode toggledSections: \(error)")
            }
            return sections
        }
        set {
            do {
                try application.userDefaults.encodeUserDefaultsObjects(newValue, key: "toggledBookmarkSections")
            } catch let error {
                DDLogError("Unable to write toggledSections: \(error)")
            }
        }
    }

    // MARK: - BookmarkEditorDelegate

    func bookmarkEditorCancelled(_ viewController: UIViewController) {
        viewController.dismiss(animated: true, completion: nil)
    }

    func bookmarkEditor(_ viewController: UIViewController, editedBookmark bookmark: Bookmark, isNewBookmark: Bool) {
        viewController.dismiss(animated: true, completion: nil)
        collectionController.reload(animated: false)
    }

    // MARK: - Data Loading

    private lazy var dataLoader = BookmarkDataLoader(application: application, delegate: self)

    public func dataLoaderDidUpdate(_ dataLoader: BookmarkDataLoader) {
        self.collectionController.reload(animated: false)
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
        collectionController.reload(animated: false)
    }
}
