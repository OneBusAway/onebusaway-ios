//
//  EditBookmarkViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Eureka
import OBAKitCore

/// This view controller offers support for creating and editing bookmarks.
class EditBookmarkViewController: FormViewController, AddGroupAlertDelegate {
    private let application: Application
    private let viewModel: EditBookmarkViewModel
    private weak var delegate: BookmarkEditorDelegate?

    convenience init(application: Application, stop: Stop, bookmark: Bookmark?, delegate: BookmarkEditorDelegate?) {
        self.init(application: application, source: .stop(stop), bookmark: bookmark, delegate: delegate)
    }

    convenience init(application: Application, arrivalDeparture: ArrivalDeparture, bookmark: Bookmark?, delegate: BookmarkEditorDelegate?) {
        self.init(application: application, source: .arrivalDeparture(arrivalDeparture), bookmark: bookmark, delegate: delegate)
    }

    private init(application: Application, source: BookmarkSource, bookmark: Bookmark?, delegate: BookmarkEditorDelegate?) {
        self.application = application
        self.delegate = delegate
        self.viewModel = EditBookmarkViewModel(application: application, source: source, bookmark: bookmark)

        super.init(nibName: nil, bundle: nil)

        if viewModel.isAddMode {
            title = Strings.addBookmark
        } else {
            title = OBALoc("edit_bookmark_controller.title_edit", value: "Edit Bookmark", comment: "Title for the Edit Bookmark controller in edit mode")
        }

        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(close))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        loadForm()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshGroupSelection()
    }

    // MARK: - Eureka Form

    private let selectedGroupTag = "groupTag"
    private let bookmarkNameTag = "name"
    private let showInTodayViewTag = "todayView"

    /// Creates, loads, and populates data in the Eureka Form object.
    private func loadForm() {
        form
            +++ bookmarkNameSection
            +++ showInTodayViewSection
            +++ selectedBookmarkGroupSection
            +++ addGroupSection

        form.setValues([
            bookmarkNameTag: viewModel.initialName,
            selectedGroupTag: viewModel.initialGroupID?.uuidString ?? "",
            showInTodayViewTag: viewModel.initialIsFavorite
        ])
    }

    /// The `Form` section that contains the Bookmark Name `TextRow`.
    private lazy var bookmarkNameSection: Section = {
        let title = OBALoc("edit_bookmark_controller.name_section.header_title", value: "Bookmark Name", comment: "Title of the Bookmark Name header.")
        let section = Section(title)
        section <<< TextRow {
            $0.tag = bookmarkNameTag
        }

        return section
    }()

    private lazy var showInTodayViewSection: Section = {
        let section = Section()

        section <<< SwitchRow(showInTodayViewTag) {
            $0.tag = showInTodayViewTag
            $0.title = OBALoc("edit_bookmark_controller.show_in_today_view_switch_title", value: "Show in Today View widget", comment: "Title next to the switch that toggles whether a bookmark will appear in the today view.")
        }

        return section
    }()

    /// The `Form` section that contains an 'Add Bookmark Group' button.
    private lazy var addGroupSection: Section = {
        let section = Section()
        section <<< ButtonRow {
            $0.title = OBALoc("edit_bookmark_controller.add_group_button_title", value: "Add Bookmark Group", comment: "Title of the button that lets the user add a new Bookmark Group.")
            $0.onCellSelection { [weak self] (_, _) in
                guard let self = self else { return }

                self.present(self.addGroupAlert.alertController, animated: true, completion: nil)
            }
        }
        return section
    }()

    /// The `Form` section that contains the list of `BookmarkGroup`s.
    private lazy var selectedBookmarkGroupSection: SelectableSection<ListCheckRow<String>> = {
        let section = SelectableSection<ListCheckRow<String>>(
            OBALoc("edit_bookmark_controller.group_section.header_title", value: "Bookmark Group", comment: "Title of the Bookmark Group header."),
            selectionType: .singleSelection(enableDeselection: false)
        )

        for group in viewModel.bookmarkGroups {
            addRow(for: group, to: section)
        }

        // `ListCheckRow<String>` requires a non-nil String, so "no group" is
        // represented as the empty string here and round-tripped back to
        // `UUID?` via `UUID(optionalUUIDString:)` in `save()`.
        section <<< ListCheckRow<String>("") {
            $0.tag = selectedGroupTag
            $0.title = OBALoc("edit_bookmark_controller.no_group_row", value: "(No Group)", comment: "Don't add this bookmark to a group.")
            $0.selectableValue = ""
        }

        return section
    }()

    /// Adds a new selectable `BookmarkGroup` row to the specified `section`.
    private func addRow(for group: BookmarkGroup, to section: SelectableSection<ListCheckRow<String>>) {
        let uuid = group.id.uuidString
        section <<< ListCheckRow<String>(uuid) {
            $0.tag = uuid
            $0.title = group.name
            $0.selectableValue = uuid
        }
    }

    // MARK: - Add Group Alert

    private lazy var addGroupAlert: AddGroupAlertController = {
        return AddGroupAlertController(dataStore: application.userDataStore, group: nil, delegate: self)
    }()

    func bookmarkGroupSaved(_ group: BookmarkGroup) {
        addRow(for: group, to: selectedBookmarkGroupSection)
    }

    // MARK: - Group Selection

    private func refreshGroupSelection() {
        let currentGroupID = viewModel.currentGroupID()?.uuidString ?? ""
        for row in selectedBookmarkGroupSection.allRows {
            guard let checkRow = row as? ListCheckRow<String> else { continue }
            checkRow.value = (checkRow.selectableValue == currentGroupID) ? checkRow.selectableValue : nil
            checkRow.updateCell()
        }
    }

    // MARK: - Actions

    /// Cancels the editor by telling the delegate, the way `save()` and
    /// `AddBookmarkViewController.cancel()` both do.
    ///
    /// Dismissing here directly would leave the delegate believing the editor is
    /// still up, which matters to any presenter that keeps its own state — a
    /// SwiftUI `.sheet(item:)` binding, for one. Every delegate dismisses us in
    /// response; the fallback covers a delegate that has been deallocated.
    @objc private func close() {
        guard let delegate else {
            dismiss(animated: true, completion: nil)
            return
        }

        delegate.bookmarkEditorCancelled(self)
    }

    @objc private func save() {
        let rawName = form.values()[bookmarkNameTag] as? String ?? ""
        let isFavorite = (form.values()[showInTodayViewTag] as? Bool) ?? true
        let rawSelectedGroupID = selectedBookmarkGroupSection.selectedRows().first?.value ?? ""
        let selectedGroupID = UUID(optionalUUIDString: rawSelectedGroupID)

        let notifyEdited: (Bookmark, Bool) -> Void = { [weak self] bookmark, isNew in
            guard let self else { return }
            self.delegate?.bookmarkEditor(self, editedBookmark: bookmark, isNewBookmark: isNew)
        }

        switch viewModel.prepareToSave(name: rawName) {
        case .regionUnavailable:
            let alert = UIAlertController(
                title: OBALoc("edit_bookmark_controller.region_error.title", value: "Unable to Save", comment: "Title of an alert shown when a bookmark cannot be saved because the current region is unavailable."),
                message: OBALoc("edit_bookmark_controller.region_error.body", value: "The current region is not available. Please try again.", comment: "Body of an alert shown when a bookmark cannot be saved because the current region is unavailable."),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: Strings.ok, style: .default, handler: nil))
            present(alert, animated: true, completion: nil)

        case .readyToSaveNew(let bookmark):
            viewModel.persistNew(bookmark, name: rawName, isFavorite: isFavorite, to: selectedGroupID)
            notifyEdited(bookmark, true)

        case .readyToSaveExisting(let bookmark):
            viewModel.persistExisting(bookmark, name: rawName, isFavorite: isFavorite, to: selectedGroupID)
            notifyEdited(bookmark, false)

        case .duplicateRequiresConfirmation(let bookmark):
            let alert = UIAlertController(
                title: OBALoc("edit_bookmark_controller.duplicate_alert.title", value: "Duplicate Bookmark", comment: "The title of an alert telling the user that they have already bookmarked this thing. Noun form of 'duplicate', not the verb."),
                message: OBALoc("edit_bookmark_controller.duplicate_alert.body", value: "You already have this bookmarked. Did you mean to create a duplicate?", comment: "Body of an alert telling the user they have already bookmarked this thing."), preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: Strings.cancel, style: .cancel, handler: { [weak self] _ in
                self?.viewModel.resolveDuplicate(.cancelled, name: rawName, isFavorite: isFavorite, to: selectedGroupID)
            }))
            alert.addAction(UIAlertAction(title: OBALoc("edit_bookmark_controller.duplicate_alert.affirmative_button", value: "Create Duplicate", comment: "Indicates that the user wants to create a duplicate bookmark."), style: .default, handler: { [weak self] _ in
                guard let self else { return }
                self.viewModel.resolveDuplicate(
                    .createDuplicate(bookmark),
                    name: rawName,
                    isFavorite: isFavorite,
                    to: selectedGroupID
                )
                notifyEdited(bookmark, true)
            }))
            present(alert, animated: true, completion: nil)
        }
    }
}
