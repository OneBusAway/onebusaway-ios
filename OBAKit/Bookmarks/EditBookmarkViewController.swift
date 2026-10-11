//
//  EditBookmarkViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// This view controller offers support for creating and editing bookmarks.
///
/// The form is `EditBookmarkView`; this controller owns the Save and Cancel
/// buttons, the save-time alerts, and the delegate callbacks.
class EditBookmarkViewController: UIHostingController<EditBookmarkView> {
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

        super.init(rootView: EditBookmarkView(viewModel: viewModel))

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

    @objc func save() {
        let rawName = viewModel.name
        let isFavorite = viewModel.isFavorite
        let selectedGroupID = viewModel.selectedGroupID

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
