//
//  AddBookmarkViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

protocol BookmarkEditorDelegate: NSObjectProtocol {
    func bookmarkEditorCancelled(_ viewController: UIViewController)
    func bookmarkEditor(_ viewController: UIViewController, editedBookmark bookmark: Bookmark, isNewBookmark: Bool)
}

/// The entry-point view controller for creating a new bookmark.
///
/// - Note: This controller expects to be presented modally.
class AddBookmarkViewController: TaskController<[ArrivalDeparture]>, OBAListViewDataSource {
    private let stop: Stop
    private weak var delegate: BookmarkEditorDelegate?

    /// This is the default initializer for `AddBookmarkViewController`.
    /// - Parameter application: The application object
    /// - Parameter stop: The `Stop` object for which a bookmark will be added. This will be used to load available `ArrivalDeparture` objects, as well.
    /// - Parameter delegate: The `BookmarkEditorDelegate` receives callbacks when this controller (and its children) are dismissed.
    ///
    /// Initialize the view controller, wrap it with a navigation controller, and then modally present it to use.
    public init(application: Application, stop: Stop, delegate: BookmarkEditorDelegate?) {
        self.stop = stop
        self.delegate = delegate

        super.init(application: application)

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))

        title = Strings.addBookmark
    }

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground
        listView.obaDataSource = self
        view.addSubview(listView)
        listView.pinToSuperview(.edges)
    }

    // MARK: - OBAListView
    let listView = OBAListView()

    func items(for listView: OBAListView) -> [OBAListViewSection] {
        return [wholeStopBookmarkSection, tripBookmarkSection]
    }

    func emptyData(for listView: OBAListView) -> OBAListView.EmptyData? {
        if let error {
            return .standard(.init(error: error))
        } else {
            return nil
        }
    }

    var wholeStopBookmarkSection: OBAListViewSection {
        let row = OBAListRowView.DefaultViewModel(title: Formatters.formattedTitle(stop: stop), accessoryType: .disclosureIndicator) { _ in
            let editStopController = EditBookmarkViewController(application: self.application, stop: self.stop, bookmark: nil, delegate: self.delegate)
            self.navigationController?.pushViewController(editStopController, animated: true)
        }

        return OBAListViewSection(id: "stop", title: OBALoc("add_bookmark_controller.bookmark_stop_header", value: "Bookmark the Stop", comment: "Text for the table header for bookmarking an entire stop."), contents: [row])
    }

    var tripBookmarkSection: OBAListViewSection {
        let sectionTitle = OBALoc("add_bookmark_controller.bookmark_trip_header", value: "Bookmark a Trip", comment: "Text for the table header for bookmarking an individual trip.")
        if let groupedElts = data?.tripKeyGroupedElements,
           let tripKeys = data?.uniqueTripKeys,
           !tripKeys.isEmpty {
            var rows = [OBAListRowView.DefaultViewModel]()
            for key in tripKeys {
                let arrDep = groupedElts[key]?.first
                let row = OBAListRowView.DefaultViewModel(title: key.routeAndHeadsign, accessoryType: .disclosureIndicator) { _ in
                    let editController = EditBookmarkViewController(application: self.application, arrivalDeparture: arrDep!, bookmark: nil, delegate: self.delegate)
                    self.navigationController?.pushViewController(editController, animated: true)
                }
                rows.append(row)
            }
            return OBAListViewSection(id: "trips", title: sectionTitle, contents: rows)
        } else {
            let explanationText = OBALoc(
                "add_bookmark_controller.trip_bookmark_unavailable",
                value: "Route bookmarks are only available when there are upcoming departures for this stop.",
                comment: "Explanatory text shown when route bookmarking is unavailable due to no upcoming departures."
            )
            var infoRow = OBAListRowView.DefaultViewModel(title: explanationText, accessoryType: .none)
            infoRow.image = UIImage(systemName: "info.circle")
            return OBAListViewSection(id: "trips", title: sectionTitle, contents: [infoRow])
        }
    }

    // MARK: - Data and UI
    override func loadData() async throws -> [ArrivalDeparture] {
        guard let apiService = application.apiService else {
            throw UnstructuredError("No API Service")
        }

        return try await apiService.getArrivalsAndDeparturesForStop(id: stop.id, minutesBefore: 30, minutesAfter: 30).entry.arrivalsAndDepartures
    }

    @MainActor
    override func updateUI() {
        listView.applyData()
    }

    // MARK: - Actions

    @objc func cancel() {
        delegate?.bookmarkEditorCancelled(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
