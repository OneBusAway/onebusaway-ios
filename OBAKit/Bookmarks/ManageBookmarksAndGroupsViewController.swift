//
//  ManageBookmarksAndGroupsViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/11/19.
//

import UIKit
import OBAKitCore

protocol ManageBookmarksDelegate: NSObjectProtocol {
    func manageBookmarksReloadData(_ controller: ManageBookmarksAndGroupsViewController)
}

/// This class is a wrapper for the Manage Groups and Manage Bookmarks
/// view controllers. It provides the user with access to both sets of
/// features through a toggle control.
///
/// See `ManageGroupsViewController` and `ManageBookmarksViewController`
/// for particulars on how the actual management works.
class ManageBookmarksAndGroupsViewController: UIViewController {
    private let application: Application
    weak var delegate: (ModalDelegate & ManageBookmarksDelegate)?

    private let groupsController: ManageGroupsViewController
    private let bookmarksController: ManageBookmarksViewController

    init(application: Application, delegate: (ModalDelegate & ManageBookmarksDelegate)?) {
        self.application = application
        self.delegate = delegate

        self.groupsController = ManageGroupsViewController(application: application)
        self.bookmarksController = ManageBookmarksViewController(application: application)

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
        groupsController.updateModelState()
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

        segment.selectedSegmentIndex = 0

        segment.addTarget(self, action: #selector(toggleControllers), for: .valueChanged)

        return segment
    }()

    @objc private func toggleControllers() {
        if controllerToggle.selectedSegmentIndex == 0 {
            removeChildController(bookmarksController)
            addChildController(groupsController)
            groupsController.view.pinToSuperview(.edges)
        }
        else {
            removeChildController(groupsController)
            addChildController(bookmarksController)
            bookmarksController.view.pinToSuperview(.edges)
        }
    }
}
