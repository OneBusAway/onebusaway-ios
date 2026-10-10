//
//  ManageBookmarksAndGroupsViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

protocol ManageBookmarksDelegate: NSObjectProtocol {
    func manageBookmarksReloadData(_ controller: ManageBookmarksAndGroupsViewController)
}

/// This class is a wrapper for the Manage Groups and Manage Bookmarks
/// view controllers. It provides the user with access to both sets of
/// features through a toggle control.
///
/// See `ManageGroupsView` and `ManageBookmarksView` for particulars on how
/// the actual management works.
class ManageBookmarksAndGroupsViewController: UIViewController {
    private let application: Application
    weak var delegate: (ModalDelegate & ManageBookmarksDelegate)?

    private let groupsViewModel: ManageGroupsViewModel
    private let bookmarksViewModel: ManageBookmarksViewModel
    private let groupsController: UIViewController
    private let bookmarksController: UIViewController

    init(application: Application, delegate: (ModalDelegate & ManageBookmarksDelegate)?) {
        self.application = application
        self.delegate = delegate

        let groupsViewModel = ManageGroupsViewModel(application: application)
        let bookmarksViewModel = ManageBookmarksViewModel(application: application)
        self.groupsViewModel = groupsViewModel
        self.bookmarksViewModel = bookmarksViewModel
        self.groupsController = UIHostingController(rootView: ManageGroupsView(viewModel: groupsViewModel))
        self.bookmarksController = UIHostingController(rootView: ManageBookmarksView(viewModel: bookmarksViewModel))

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.titleView = controllerToggle
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: Strings.close, style: .plain, target: self, action: #selector(close))

        toggleControllers()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        groupsViewModel.commit()
        bookmarksViewModel.restoreEmptyBookmarkNames()
        delegate?.manageBookmarksReloadData(self)
    }

    // MARK: - Actions

    @objc private func close() {
        delegate?.dismissModalController(self)
    }

    // MARK: - Controller Toggle

    /// A segmented control that allows the user to toggle between the groups and bookmarks controllers.
    private lazy var controllerToggle: UISegmentedControl = {
        let segment = UISegmentedControl.autolayoutNew()

        segment.insertSegment(withTitle: OBALoc("manage_bookmarks_groups.toggle.groups", value: "Groups", comment: "Segmented control item for Groups"), at: 0, animated: false)
        segment.insertSegment(withTitle: OBALoc("manage_bookmarks_groups.toggle.bookmarks", value: "Bookmarks", comment: "Segmented control item for bookmarks"), at: 1, animated: false)

        // Open on Bookmarks: deleting or renaming one is the common reason to tap Edit (#481).
        segment.selectedSegmentIndex = 1

        segment.addTarget(self, action: #selector(toggleControllers), for: .valueChanged)

        return segment
    }()

    @objc private func toggleControllers() {
        if controllerToggle.selectedSegmentIndex == 0 {
            bookmarksViewModel.restoreEmptyBookmarkNames()
            removeChildController(bookmarksController)
            addChildController(groupsController)
            groupsController.view.pinToSuperview(.edges)
        }
        else {
            // Persist group additions/deletions/renames so the bookmarks
            // tab sees the current groups when it rebuilds its sections.
            groupsViewModel.commit()
            bookmarksViewModel.reloadRows()
            removeChildController(groupsController)
            addChildController(bookmarksController)
            bookmarksController.view.pinToSuperview(.edges)
        }
    }
}
