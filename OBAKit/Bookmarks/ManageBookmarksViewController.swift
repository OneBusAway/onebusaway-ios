//
//  ManageBookmarksViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/11/19.
//

import UIKit
import Eureka
import OBAKitCore

class ManageBookmarksViewController: FormViewController {
    private let application: Application

    init(application: Application) {
        self.application = application

        super.init(nibName: nil, bundle: nil)

        resetBookmarksSections()

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
        resetBookmarksSections()
        form.removeAll()
        for s in bookmarksSections {
            form +++ s
        }
    }

    // MARK: - TableView Delegate Overrides

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard let bookmark = bookmarkForBookmarkIndexPath(sourceIndexPath) else {
            return
        }

        let destinationGroup = groupForBookmarkIndexPath(destinationIndexPath)

        application.userDataStore.add(bookmark, to: destinationGroup)
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard
            let bookmark = bookmarkForBookmarkIndexPath(indexPath),
            editingStyle == .delete
        else {
            return
        }

        _ = application.userDataStore.delete(bookmark: bookmark)

        super.tableView(tableView, commit: editingStyle, forRowAt: indexPath)
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    override func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
        return proposedDestinationIndexPath
    }

    // MARK: - Bookmarks/Index Paths

    private func groupForBookmarkIndexPath(_ indexPath: IndexPath) -> BookmarkGroup? {
        let section = bookmarksSections[indexPath.section]

        guard
            section.tag != ungroupedSectionTag,
            let sectionID = UUID(optionalUUIDString: section.tag)
        else {
            return nil
        }

        return application.userDataStore.findGroup(id: sectionID)
    }

    private func bookmarkForBookmarkIndexPath(_ indexPath: IndexPath) -> Bookmark? {
        let section = bookmarksSections[indexPath.section]
        let row = section.allRows[indexPath.row] as! NameRow // swiftlint:disable:this force_cast
        guard let id = UUID(optionalUUIDString: row.tag) else { return nil }

        return application.userDataStore.findBookmark(id: id)
    }

    // MARK: - Bookmarks/UI

    private var bookmarksSections: [MultivaluedSection]!

    private func resetBookmarksSections() {
        var sections = application.userDataStore.bookmarkGroups.map { self.buildBookmarkSection(group: $0) }
        sections.append(buildUngroupedBookmarkSection())

        bookmarksSections = sections
    }

    private func buildBookmarkSection(group: BookmarkGroup) -> MultivaluedSection {
        let bookmarks = application.userDataStore.bookmarksInGroup(group)
        let section = MultivaluedSection(multivaluedOptions: [.Reorder, .Delete], header: group.name, footer: "") {
            $0.tag = group.id.uuidString
            for bm in bookmarks {
                $0 <<< NameRow {
                    $0.tag = bm.id.uuidString
                    $0.value = bm.name
                }
            }
        }
        return section
    }

    private let ungroupedSectionTag = "ungrouped"

    private func buildUngroupedBookmarkSection() -> MultivaluedSection {
        let footer = OBALoc("manage_bookmarks.controller_footer", value: "You can rearrange and delete Bookmarks from this screen.", comment: "Explains the purpose of the Manage Bookmarks controller")
        return MultivaluedSection(multivaluedOptions: [.Reorder, .Delete], header: Strings.bookmark, footer: footer) {
            $0.tag = ungroupedSectionTag
            for bm in application.userDataStore.bookmarksInGroup(nil) {
                $0 <<< NameRow {
                    $0.tag = bm.id.uuidString
                    $0.value = bm.name
                }
            }
        }
    }

    // MARK: - Model State

    func updateModelState() {
        for section in bookmarksSections {
            let group: BookmarkGroup?
            if let id = UUID(optionalUUIDString: section.tag) {
                group = application.userDataStore.findGroup(id: id)
            }
            else {
                group = nil
            }

            for row in section.allRows {
                let row = row as! NameRow // swiftlint:disable:this force_cast
                guard
                    let bookmarkID = UUID(optionalUUIDString: row.tag),
                    let bookmark = application.userDataStore.findBookmark(id: bookmarkID)
                else {
                    continue
                }

                if let name = row.value?.strip(), name.count > 0 {
                    bookmark.name = name
                }

                application.userDataStore.add(bookmark, to: group)
            }
        }
    }
}
