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

/// The view controller that powers the Bookmarks tab of the app.
@objc(OBABookmarksViewController)
public class BookmarksViewController: UIViewController,
    AppContext,
    BookmarkEditorDelegate,
    ListAdapterDataSource,
    ListProvider,
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
        cancelUpdates()
    }

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground
        addChildController(collectionController)
        collectionController.view.pinToSuperview(.edges)
        collectionController.collectionView.addSubview(refreshControl)

        loadData()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        application.notificationCenter.addObserver(self, selector: #selector(applicationEnteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)

        collectionController.reload(animated: false)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        application.notificationCenter.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)

        timer?.invalidate()
    }

    // MARK: - Refresh Control

    @objc private func refreshControlPulled() {
        loadData()
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
                arrDeps = self.tripBookmarkKeys[key, default: []]
            }

            return BookmarkArrivalData(bookmark: bm, arrivalDepartures: arrDeps, selected: didSelectBookmark(_:), deleted: didDeleteBookmark(_:), edited: didEditBookmark(_:))
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
        let emptyView = EmptyDataSetView(frame: view.bounds)
        emptyView.titleLabel.text = OBALoc("bookmarks_controller.empty_set.title", value: "No Bookmarks", comment: "Title for the empty set indicator on the Bookmarks view controller.")
        emptyView.bodyLabel.text = OBALoc("bookmarks_controller.empty_set.body", value: "Add a bookmark for a stop or trip to easily access it here.", comment: "Body for the empty set indicator on the Bookmarks view controller.")

        return emptyView
    }

    // MARK: - Bookmark Actions

    private func didSelectBookmark(_ bookmark: Bookmark) {
        application.viewRouter.navigateTo(stop: bookmark.stop, from: self)
    }

    private func didDeleteBookmark(_ bookmark: Bookmark) {
        _ = application.userDataStore.delete(bookmark: bookmark)
        collectionController.reload(animated: true)
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

    /// An ephemeral store of toggled sections.
    private var toggledSections = [String: BookmarkSectionState]()

    // MARK: - BookmarkEditorDelegate

    func bookmarkEditorCancelled(_ viewController: UIViewController) {
        viewController.dismiss(animated: true, completion: nil)
    }

    func bookmarkEditor(_ viewController: UIViewController, editedBookmark bookmark: Bookmark) {
        viewController.dismiss(animated: true, completion: nil)
        collectionController.reload(animated: false)
    }

    // MARK: - Data Loading

    private var operations = [Operation]()

    private func loadData() {
        cancelUpdates()
        for bookmark in application.userDataStore.bookmarks {
            loadData(bookmark: bookmark)
        }
        startRefreshTimer()
    }

    private func loadData(bookmark: Bookmark) {
        guard let modelService = application.restAPIModelService else { return }

        let op = modelService.getArrivalsAndDeparturesForStop(id: bookmark.stopID, minutesBefore: 0, minutesAfter: 60)
        op.then { [weak self] in
            guard
                let self = self,
                let keysAndDeps = op.stopArrivals?.arrivalsAndDepartures.tripKeyGroupedElements
            else {
                return
            }

            for (key, deps) in keysAndDeps {
                self.tripBookmarkKeys[key] = deps
            }

            self.collectionController.reload(animated: false)
        }
        operations.append(op)
    }

    private func cancelUpdates() {
        timer?.invalidate()

        for op in operations {
            op.cancel()
        }
    }

    // MARK: - Trip Bookmark Data

    /// A dictionary that maps each bookmark to `ArrivalDeparture`s.
    /// This is used to update the UI when new `ArrivalDeparture` objects are loaded.
    private var tripBookmarkKeys = [TripBookmarkKey: [ArrivalDeparture]]()

    // MARK: - Refreshing

    private let refreshInterval = 30.0

    private var timer: Timer?

    private func startRefreshTimer() {
        timer?.invalidate()

        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.loadData()
        }
    }

    // MARK: - Notifications

    @objc private func applicationEnteredBackground(note: Notification) {
        cancelUpdates()
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
