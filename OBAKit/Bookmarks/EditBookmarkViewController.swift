//
//  EditBookmarkViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/23/19.
//

import UIKit
import Eureka
import OBAKitCore

/// This view controller offers support for creating and editing bookmarks.
class EditBookmarkViewController: FormViewController, AddGroupAlertDelegate {
    private let application: Application
    private let stop: Stop?
    private let arrivalDeparture: ArrivalDeparture?
    private let bookmark: Bookmark?
    private weak var delegate: BookmarkEditorDelegate?

    convenience init(application: Application, stop: Stop, bookmark: Bookmark?, delegate: BookmarkEditorDelegate?) {
        self.init(application: application, stop: stop, arrivalDeparture: nil, bookmark: bookmark, delegate: delegate)
    }

    convenience init(application: Application, arrivalDeparture: ArrivalDeparture, bookmark: Bookmark?, delegate: BookmarkEditorDelegate?) {
        self.init(application: application, stop: nil, arrivalDeparture: arrivalDeparture, bookmark: bookmark, delegate: delegate)
    }

    private init(application: Application, stop: Stop?, arrivalDeparture: ArrivalDeparture?, bookmark: Bookmark?, delegate: BookmarkEditorDelegate?) {
        self.application = application
        self.stop = stop
        self.arrivalDeparture = arrivalDeparture
        self.bookmark = bookmark
        self.delegate = delegate

        super.init(nibName: nil, bundle: nil)

        if self.bookmark == nil {
            title = OBALoc("edit_bookmark_controller.title_add", value: "Add Bookmark", comment: "Title for the Edit Bookmark controller in add mode")
        }
        else {
            title = OBALoc("edit_bookmark_controller.title_edit", value: "Edit Bookmark", comment: "Title for the Edit Bookmark controller in edit mode")
        }

        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        loadForm()
    }

    // MARK: - Data Helpers

    /// Determines the selected bookmark group from the form.
    private var selectedBookmarkGroup: BookmarkGroup? {
        guard let id = UUID(optionalUUIDString: selectedBookmarkGroupSection.selectedRows().first?.value) else {
            return nil
        }

        return application.userDataStore.findGroup(id: id)
    }

    private var dataObjectName: String {
        if let stop = stop {
            return Formatters.formattedTitle(stop: stop)
        }
        else {
            return arrivalDeparture!.routeAndHeadsign
        }
    }

    // MARK: - Eureka Form

    private let selectedGroupTag = "groupTag"
    private let bookmarkNameTag = "name"

    /// Creates, loads, and populates data in the Eureka Form object.
    private func loadForm() {
        form
            +++ bookmarkNameSection
            +++ selectedBookmarkGroupSection
            +++ addGroupSection

        let name = bookmark?.name ?? dataObjectName
        let groupID = bookmark?.groupID?.uuidString ?? ""

        form.setValues([bookmarkNameTag: name, selectedGroupTag: groupID])
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

        for group in application.userDataStore.bookmarkGroups {
            addRow(for: group, to: section)
        }

        section <<< ListCheckRow<String>("") {
            $0.tag = selectedGroupTag
            $0.title = OBALoc("edit_bookmark_controller.no_group_row", value: "(No Group)", comment: "Don't add this bookmark to a group.")
            $0.selectableValue = ""
        }

        return section
    }()

    /// Adds a new selectable `BookmarkGroup` row to the specified `section`.
    /// - Parameter group: The `BookmarkGroup` to add to the section.
    /// - Parameter section: The `SelectableSection` to which the group will be added.
    private func addRow(for group: BookmarkGroup, to section: SelectableSection<ListCheckRow<String>>) {
        let uuid = group.id.uuidString
        section <<< ListCheckRow<String>(uuid) {
            $0.tag = selectedGroupTag
            $0.title = group.name
            $0.selectableValue = uuid
        }
    }

    // MARK: - Add Group Alert

    /// A wrapper object that allows the user to create a new `BookmarkGroup`
    private lazy var addGroupAlert: AddGroupAlertController = {
        return AddGroupAlertController(dataStore: application.userDataStore, group: nil, delegate: self)
    }()

    /// A callback that fires when the user creates a new `BookmarkGroup` through the `addGroupAlert`
    func bookmarkGroupSaved(_ group: BookmarkGroup) {
        addRow(for: group, to: selectedBookmarkGroupSection)
    }

    // MARK: - Actions

    @objc private func save() {
        guard
            let name = form.values()[bookmarkNameTag] as? String,
            let region = application.currentRegion
        else { return }

        let addMode = self.bookmark == nil

        let bookmark: Bookmark

        if addMode {
            if let stop = stop {
                bookmark = Bookmark(name: name, regionIdentifier: region.regionIdentifier, stop: stop)
            }
            else if let arrivalDeparture = arrivalDeparture {
                bookmark = Bookmark(name: name, regionIdentifier: region.regionIdentifier, arrivalDeparture: arrivalDeparture, stop: arrivalDeparture.stop)

                let analyticsValue = AnalyticsLabels.addRemoveBookmarkValue(routeID: arrivalDeparture.routeID, headsign: arrivalDeparture.tripHeadsign, stopID: arrivalDeparture.stopID)
                application.analytics?.reportEvent(.userAction, label: AnalyticsLabels.addBookmark, value: analyticsValue)
            }
            else {
                fatalError()
            }
        }
        else {
            bookmark = self.bookmark!
            bookmark.name = name
        }

        application.userDataStore.add(bookmark, to: selectedBookmarkGroup)
        delegate?.bookmarkEditor(self, editedBookmark: bookmark)
    }
}
