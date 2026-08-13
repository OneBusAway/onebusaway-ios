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
    private let viewModel: ManageBookmarksViewModel

    init(application: Application) {
        self.viewModel = ManageBookmarksViewModel(application: application)

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

    /// Rebuilds the form from the current userDataStore on the next run loop iteration.
    /// Deferral avoids index-out-of-bounds inside Eureka during child controller transitions.
    /// See: https://github.com/OneBusAway/onebusaway-ios/issues/922
    func reloadFormFromStore() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            UIView.performWithoutAnimation {
                self.loadForm()
            }
        }
    }

    // MARK: - TableView Delegate Overrides

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard let bookmark = bookmarkForBookmarkIndexPath(sourceIndexPath) else {
            return
        }

        let destinationGroup = groupForBookmarkIndexPath(destinationIndexPath)
        viewModel.moveBookmark(bookmark, to: destinationGroup, at: destinationIndexPath.row)

        // Defer refresh to avoid index-out-of-bounds during Eureka's internal animation.
        // See: https://github.com/OneBusAway/onebusaway-ios/issues/922
        reloadFormFromStore()
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard
            let bookmark = bookmarkForBookmarkIndexPath(indexPath),
            editingStyle == .delete
        else {
            return
        }

        viewModel.deleteBookmark(bookmark)

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

        return viewModel.findGroup(id: sectionID)
    }

    private func bookmarkForBookmarkIndexPath(_ indexPath: IndexPath) -> Bookmark? {
        let section = bookmarksSections[indexPath.section]
        guard let row = section.allRows[indexPath.row] as? NameRow else {
            Logger.warn("bookmarkForBookmarkIndexPath: Expected NameRow at \(indexPath)")
            return nil
        }
        guard let id = UUID(optionalUUIDString: row.tag) else {
            Logger.warn("bookmarkForBookmarkIndexPath: NameRow at \(indexPath) has non-UUID tag \(row.tag ?? "nil")")
            return nil
        }

        return viewModel.findBookmark(id: id)
    }

    // MARK: - Bookmarks/UI

    private var bookmarksSections: [MultivaluedSection]!

    private func resetBookmarksSections() {
        var sections = viewModel.bookmarkGroups.map { self.buildBookmarkSection(group: $0) }
        sections.append(buildUngroupedBookmarkSection())

        bookmarksSections = sections
    }

    private func buildBookmarkSection(group: BookmarkGroup) -> MultivaluedSection {
        let bookmarks = viewModel.bookmarksInGroup(group)
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
            for bm in viewModel.bookmarksInGroup(nil) {
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
        guard let bookmarkID = UUID(optionalUUIDString: row.tag), let newName = row.value else {
            return
        }
        viewModel.saveNameChange(bookmarkID: bookmarkID, newName: newName)
    }

    /// Called when the user closes the screen. Any bookmark whose name field
    /// was left empty gets its original transit-derived name restored.
    func restoreEmptyBookmarkNames() {
        for section in bookmarksSections {
            for row in section.allRows {
                guard let nameRow = row as? NameRow else { continue }
                let trimmed = nameRow.value?.trimmingCharacters(in: .whitespaces) ?? ""
                guard trimmed.isEmpty else { continue }

                guard
                    let bookmarkID = UUID(optionalUUIDString: nameRow.tag),
                    let bookmark = viewModel.findBookmark(id: bookmarkID)
                else {
                    continue
                }

                viewModel.restoreTransitName(for: bookmark)
            }
        }
    }
}
