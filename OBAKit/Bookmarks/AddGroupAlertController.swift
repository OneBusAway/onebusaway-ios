//
//  AddGroupAlertController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/25/19.
//

import UIKit
import OBAKitCore

protocol AddGroupAlertDelegate: NSObjectProtocol {
    func bookmarkGroupSaved(_ group: BookmarkGroup)
}

/// An alert-style controller that allows creating new and editing existing `BookmarkGroup`s.
class AddGroupAlertController: NSObject {

    private let dataStore: UserDataStore
    private var group: BookmarkGroup?
    public let alertController: UIAlertController
    public weak var delegate: AddGroupAlertDelegate?

    init(dataStore: UserDataStore, group: BookmarkGroup?, delegate: AddGroupAlertDelegate?) {
        self.dataStore = dataStore
        self.delegate = delegate

        let title = NSLocalizedString("add_group_alert.title", value: "Add Group", comment: "Title of the Add Bookmark Group controller")

        self.alertController = UIAlertController(title: title, message: nil, preferredStyle: .alert)

        super.init()

        self.alertController.addTextField { textField in
            textField.placeholder = NSLocalizedString("add_group_alert.placeholder", value: "Bookmark Group Title", comment: "Text field placeholder on the Add Group Alert.")
            textField.text = group?.name
        }

        self.alertController.addAction(UIAlertAction.cancelAction)
        self.alertController.addAction(title: Strings.save) { [weak self] _ in
            guard
                let self = self,
                let textField = self.alertController.textFields?.first,
                let text = textField.text
            else { return }

            self.saveChanges(text)
        }
    }

    private func saveChanges(_ text: String) {
        let group = self.group ?? BookmarkGroup(name: text, sortOrder: Int.max)
        group.name = text

        dataStore.upsert(bookmarkGroup: group)
        delegate?.bookmarkGroupSaved(group)
    }
}
