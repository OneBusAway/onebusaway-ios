//
//  AddBookmarkViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/23/19.
//

import UIKit
import AloeStackView
import OBAKitCore

protocol BookmarkEditorDelegate: NSObjectProtocol {
    func bookmarkEditorCancelled(_ viewController: UIViewController)
    func bookmarkEditor(_ viewController: UIViewController, editedBookmark bookmark: Bookmark, isNewBookmark: Bool)
}

/// The entry-point view controller for creating a new bookmark.
///
/// - Note: This controller expects to be presented modally.
class AddBookmarkViewController: OperationController<StopArrivalsModelOperation, [ArrivalDeparture]>, AloeStackTableBuilder {
    private let stop: Stop
    private weak var delegate: BookmarkEditorDelegate?

    lazy var stackView = AloeStackView.autolayoutNew(
        backgroundColor: ThemeColors.shared.groupedTableBackground
    )

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

        title = OBALoc("add_bookmark_controller.title", value: "Add Bookmark", comment: "Title for the Add Bookmark view controller.")
    }

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(stackView)
        stackView.pinToSuperview(.edges)
    }

    // MARK: - Data and UI

    override func loadData() -> StopArrivalsModelOperation? {
        guard let modelService = application.restAPIModelService else { return nil }

        let op = modelService.getArrivalsAndDeparturesForStop(id: stop.id, minutesBefore: 30, minutesAfter: 30)
        op.then { [weak self] in
            guard let self = self else { return }
            self.data = op.stopArrivals?.arrivalsAndDepartures
        }

        return op
    }

    override func updateUI() {
        addWholeStopBookmarkSection()
        addTripBookmarkSection()
    }

    // MARK: - UI Builders

    private func addWholeStopBookmarkSection() {
        addGroupedTableHeaderToStack(headerText: OBALoc("add_bookmark_controller.bookmark_stop_header", value: "Bookmark the Stop", comment: "Text for the table header for bookmarking an entire stop."))
        let stopRow = DefaultTableRowView(title: Formatters.formattedTitle(stop: stop), accessoryType: .disclosureIndicator)
        addGroupedTableRowToStack(stopRow, isLastRow: true) { [weak self] _ in
            guard let self = self else { return }

            let editStopController = EditBookmarkViewController(application: self.application, stop: self.stop, bookmark: nil, delegate: self.delegate)
            self.navigationController?.pushViewController(editStopController, animated: true)
        }
    }

    private func addTripBookmarkSection() {
        guard
            let groupedElts = data?.tripKeyGroupedElements,
            let tripKeys = data?.uniqueTripKeys,
            tripKeys.count > 0
        else { return }

        addGroupedTableHeaderToStack(headerText: OBALoc("add_bookmark_controller.bookmark_trip_header", value: "Bookmark a Trip", comment: "Text for the table header for bookmarking an individual trip."))

        for key in tripKeys {
            let arrDep = groupedElts[key]?.first
            let tripRow = DefaultTableRowView(title: key.routeAndHeadsign, accessoryType: .disclosureIndicator)
            addGroupedTableRowToStack(tripRow, isLastRow: false) { [weak self] _ in
                guard let self = self else { return }
                let editController = EditBookmarkViewController(application: self.application, arrivalDeparture: arrDep!, bookmark: nil, delegate: self.delegate)
                self.navigationController?.pushViewController(editController, animated: true)
            }
        }

        if let lastRow = stackView.lastRow {
            stackView.setSeparatorInset(forRow: lastRow, inset: .zero)
        }
    }

    // MARK: - Actions

    @objc func cancel() {
        delegate?.bookmarkEditorCancelled(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
