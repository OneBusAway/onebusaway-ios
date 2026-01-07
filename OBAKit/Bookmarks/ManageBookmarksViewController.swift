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
import QuartzCore

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

    private var pendingReloadWork: DispatchWorkItem?

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard let bookmark = bookmarkForBookmarkIndexPath(sourceIndexPath) else {
            return
        }

        let destinationGroup = groupForBookmarkIndexPath(destinationIndexPath)
        application.userDataStore.add(bookmark, to: destinationGroup, index: destinationIndexPath.row)

        // Cancel any pending reload to handle rapid reordering
        pendingReloadWork?.cancel()

        // Refreshing immediately causes index-out-of-bounds in Eureka.
        // See: https://github.com/OneBusAway/onebusaway-ios/issues/922
        // Use CATransaction to properly wait for the move animation to complete.
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.loadForm()
        }
        CATransaction.commit()

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
}
