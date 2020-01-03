//
//  ManageGroupsViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 9/21/19.
//

import UIKit
import Eureka
import OBAKitCore

class ManageGroupsViewController: FormViewController {
    private let application: Application

    init(application: Application) {
        self.application = application

        super.init(nibName: nil, bundle: nil)

        title = OBALoc("manage_groups_controller.title", value: "Edit Bookmarks", comment: "Manage Groups controller title")
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UIViewController

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadForm()
        tableView.setEditing(true, animated: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        updateModelState()
    }

    // MARK: - Form Builders

    /// Creates, loads, and populates data in the Eureka Form object.
    private func loadForm() {
        form.removeAll()
        form +++ groupsSection
    }

    // MARK: - Groups Section

    private lazy var groupsSection = MultivaluedSection(multivaluedOptions: [.Reorder, .Insert, .Delete], header: "", footer: OBALoc("manage_groups_controller.groups.footer_text", value: "You can rename, add, delete, and rearrange bookmark groups. Bookmarks in deleted groups are not deleted.", comment: "Footer explanation on the Groups section of the Manage Groups controller.")) {
        $0.header = HeaderFooterView<UIView>(HeaderFooterProvider.class)
        $0.header?.height = { CGFloat.leastNormalMagnitude }
        $0.tag = "group_tag"
        $0.addButtonProvider = { _ in
            ButtonRow {
                $0.title = OBALoc("manage_groups_controller.add_group_button", value: "Add Bookmark Group", comment: "'Add Bookmark Group' button text")
            }
        }
        $0.multivaluedRowToInsertAt = { _ in
            ManageGroupsViewController.buildNameRow()
        }

        if application.userDataStore.bookmarkGroups.count == 0 {
            $0 <<< ManageGroupsViewController.buildNameRow()
        }
        else {
            for group in application.userDataStore.bookmarkGroups {
                $0 <<< ManageGroupsViewController.buildNameRow(tag: group.id.uuidString, value: group.name)
            }
        }
    }

    private class func buildNameRow(tag: String? = nil, value: String? = nil) -> NameRow {
        NameRow {
            $0.tag = tag
            $0.value = value
            $0.placeholder = OBALoc("manage_groups_controller.text_field_placeholder", value: "Group name", comment: "Placeholder text for Bookmark Group.")
        }
    }

    // MARK: - Model State

    func updateModelState() {
        let nameRows = groupsSection.allRows.filter { $0 is NameRow } as! [NameRow] // swiftlint:disable:this force_cast
        let newGroups = nameRows.bookmarkGroups
        application.userDataStore.replaceBookmarkGroups(with: newGroups)
    }
}

// MARK: - Private Helpers

fileprivate extension Array where Element == NameRow {
    var bookmarkGroups: [BookmarkGroup] {
        var groups = [BookmarkGroup]()

        for index in 0..<count {
            let elt = self[index]

            if let name = elt.value, name.count > 0 {
                let id = UUID(optionalUUIDString: elt.tag) ?? UUID()
                groups.append(BookmarkGroup(name: name, id: id, sortOrder: index))
            }
        }

        return groups
    }
}
