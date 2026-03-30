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
import OBAKitCore
import WidgetKit

/// The view controller that powers the Bookmarks tab of the app.
/// Hosts a SwiftUI BookmarksView while preserving all existing navigation,
/// editing, and delegate behaviour.
@objc(OBABookmarksViewController)
public class BookmarksViewController: UIViewController,
                                      AppContext,
                                      BookmarkEditorDelegate,
                                      ManageBookmarksDelegate,
                                      ModalDelegate {

    public let application: Application

    private let bookmarksViewModel: BookmarksSwiftUIViewModel
    private var hostingController: UIHostingController<BookmarksView>!

    // MARK: - Init

    public init(application: Application) {
        self.application = application
        self.bookmarksViewModel = BookmarksSwiftUIViewModel(application: application)

        super.init(nibName: nil, bundle: nil)

        title = OBALoc("bookmarks_controller.title", value: "Bookmarks", comment: "Title of the Bookmarks tab")
        tabBarItem.image = Icons.bookmarksTabIcon
        tabBarItem.selectedImage = Icons.bookmarksSelectedTabIcon
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        bookmarksViewModel.cancelUpdatesSync()
    }

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        // Left: Edit (manage groups/bookmarks)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: OBALoc("bookmarks_controller.groups_button_title",
                          value: "Edit",
                          comment: "Groups button title in Bookmarks controller"),
            style: .plain,
            target: self,
            action: #selector(manageGroups)
        )

        // Right: Sort menu
        rebuildSortMenu()

        // Embed SwiftUI view
        var swiftUIView = BookmarksView(viewModel: bookmarksViewModel)
        swiftUIView.hostViewController = self
        swiftUIView.application = application

        hostingController = UIHostingController(rootView: swiftUIView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)

        bookmarksViewModel.loadData()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        application.notificationCenter.addObserver(
            self,
            selector: #selector(applicationEnteredBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        bookmarksViewModel.rebuildSections()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        application.notificationCenter.removeObserver(
            self,
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        bookmarksViewModel.cancelUpdates()
    }

    // MARK: - Sort Menu

    private func rebuildSortMenu() {
        let groupAction = UIAction(
            title: OBALoc("bookmarks_controller.sort_menu.sort_by_group",
                          value: "Sort by Group",
                          comment: "A menu item that allows the user to sort their bookmarks into groups."),
            image: UIImage(systemName: "folder"),
            state: bookmarksViewModel.sortMode == .byGroup ? .on : .off
        ) { [weak self] _ in
            self?.bookmarksViewModel.sortMode = .byGroup
            self?.rebuildSortMenu()
        }

        let distanceAction = UIAction(
            title: OBALoc("bookmarks_controller.sort_menu.sort_by_distance",
                          value: "Sort by Distance",
                          comment: "A menu item that allows the user to sort their bookmarks by distance from the user."),
            image: UIImage(systemName: "location.circle"),
            state: bookmarksViewModel.sortMode == .byDistance ? .on : .off
        ) { [weak self] _ in
            self?.bookmarksViewModel.sortMode = .byDistance
            self?.rebuildSortMenu()
        }

        let menu = UIMenu(title: Strings.sort, options: .displayInline, children: [groupAction, distanceAction])
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "MORE",
            image: UIImage(systemName: "arrow.up.arrow.down.circle"),
            menu: menu
        )
    }

    // MARK: - Manage Groups

    @objc private func manageGroups() {
        let manageController = ManageBookmarksAndGroupsViewController(application: application, delegate: self)
        let nav = UINavigationController(rootViewController: manageController)
        application.viewRouter.present(nav, from: self)
    }

    // MARK: - Background notification

    @objc private func applicationEnteredBackground() {
        bookmarksViewModel.cancelUpdates()
    }

    // MARK: - BookmarkEditorDelegate

    public func bookmarkEditorCancelled(_ viewController: UIViewController) {
        viewController.dismiss(animated: true)
    }

    public func bookmarkEditor(_ viewController: UIViewController, editedBookmark bookmark: Bookmark, isNewBookmark: Bool) {
        viewController.dismiss(animated: true)
        bookmarksViewModel.rebuildSections()
    }

    // MARK: - ManageBookmarksDelegate

    func manageBookmarksReloadData(_ controller: ManageBookmarksAndGroupsViewController) {
        bookmarksViewModel.rebuildSections()
    }

    // MARK: - ModalDelegate

    public func dismissModalController(_ controller: UIViewController) {
        controller.dismiss(animated: true)
    }
}
