//
//  ManageBookmarksViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
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

    override func viewDidLoad() {
        super.viewDidLoad()
        loadForm()
        tableView.setEditing(true, animated: false)
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
        application.userDataStore.add(bookmark, to: destinationGroup, index: destinationIndexPath.row)

        // Defer refresh to avoid index-out-of-bounds during Eureka's internal animation.
        // Use performWithoutAnimation to prevent visual glitches.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            UIView.performWithoutAnimation {
                self.loadForm()
            }
        }
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard
            let bookmark = bookmarkForBookmarkIndexPath(indexPath),
            editingStyle == .delete
        else {
            return
        }

        if let routeID = bookmark.routeID, let headsign = bookmark.tripHeadsign {
            application.analytics?.reportEvent(pageURL: "app://localhost/bookmarks", label: AnalyticsLabels.removeBookmark, value: AnalyticsLabels.addRemoveBookmarkValue(routeID: routeID, headsign: headsign, stopID: bookmark.stopID))
        }
        application.userDataStore.delete(bookmark: bookmark)

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
        guard let row = section.allRows[indexPath.row] as? NameRow,
              let id = UUID(optionalUUIDString: row.tag) else {
            return nil
        }

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
                }.onChange { [weak self] row in
                    self?.saveBookmarkNameChange(row: row)
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
                }.onChange { [weak self] row in
                    self?.saveBookmarkNameChange(row: row)
                }
            }
        }
    }

    // MARK: - Bookmark Name Updates

    private func saveBookmarkNameChange(row: NameRow) {
        guard
            let bookmarkID = UUID(optionalUUIDString: row.tag),
            let newName = row.value,
            !newName.trimmingCharacters(in: .whitespaces).isEmpty,
            let bookmark = application.userDataStore.findBookmark(id: bookmarkID)
        else {
            return
        }

        // Look up current group from bookmark's groupID
        let currentGroup = bookmark.groupID.flatMap {
            application.userDataStore.findGroup(id: $0)
        }

        bookmark.name = newName
        application.userDataStore.add(bookmark, to: currentGroup)
    }
}
