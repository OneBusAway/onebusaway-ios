//
//  AddBookmarkViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/23/19.
//

import UIKit
import IGListKit
import OBAKitCore

protocol BookmarkEditorDelegate: NSObjectProtocol {
    func bookmarkEditorCancelled(_ viewController: UIViewController)
    func bookmarkEditor(_ viewController: UIViewController, editedBookmark bookmark: Bookmark, isNewBookmark: Bool)
}

/// The entry-point view controller for creating a new bookmark.
///
/// - Note: This controller expects to be presented modally.
class AddBookmarkViewController: OperationController<DecodableOperation<RESTAPIResponse<StopArrivals>>, [ArrivalDeparture]>, HasTableStyle, ListAdapterDataSource {
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
        addChildController(collectionController)
        collectionController.view.pinToSuperview(.edges)
    }

    // MARK: - IGListKit

    private lazy var collectionController = CollectionController(application: application, dataSource: self, style: tableStyle)

    let tableStyle = TableCollectionStyle.grouped

    func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        var sections = [ListDiffable]()
        sections.append(contentsOf: wholeStopBookmarkSection)
        sections.append(contentsOf: tripBookmarkSection)
        return sections
    }

    func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
        return defaultSectionController(for: object)
    }

    func emptyView(for listAdapter: ListAdapter) -> UIView? {
        return nil
    }

    private var wholeStopBookmarkSection: [ListDiffable] {
        let row = TableRowData(title: Formatters.formattedTitle(stop: stop), accessoryType: .disclosureIndicator) { [weak self] _ in
            guard let self = self else { return }

            let editStopController = EditBookmarkViewController(application: self.application, stop: self.stop, bookmark: nil, delegate: self.delegate)
            self.navigationController?.pushViewController(editStopController, animated: true)
        }
        return [
            TableHeaderData(title: OBALoc("add_bookmark_controller.bookmark_stop_header", value: "Bookmark the Stop", comment: "Text for the table header for bookmarking an entire stop.")),
            TableSectionData(row: row)
        ]
    }

    private var tripBookmarkSection: [ListDiffable] {
        guard
            let groupedElts = data?.tripKeyGroupedElements,
            let tripKeys = data?.uniqueTripKeys,
            tripKeys.count > 0
        else { return [] }

        var rows = [TableRowData]()

        for key in tripKeys {
            let arrDep = groupedElts[key]?.first
            let row = TableRowData(title: key.routeAndHeadsign, accessoryType: .disclosureIndicator) { [weak self] _ in
                guard let self = self else { return }
                let editController = EditBookmarkViewController(application: self.application, arrivalDeparture: arrDep!, bookmark: nil, delegate: self.delegate)
                self.navigationController?.pushViewController(editController, animated: true)
            }
            rows.append(row)
        }

        return [
            TableHeaderData(title: OBALoc("add_bookmark_controller.bookmark_trip_header", value: "Bookmark a Trip", comment: "Text for the table header for bookmarking an individual trip.")),
            TableSectionData(rows: rows)
        ]
    }

    // MARK: - Data and UI

    override func loadData() -> DecodableOperation<RESTAPIResponse<StopArrivals>>? {
        guard let apiService = application.restAPIService else { return nil }

        let op = apiService.getArrivalsAndDeparturesForStop(id: stop.id, minutesBefore: 30, minutesAfter: 30)
        op.complete { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                print("TODO FIXME handle error! \(error)")
            case .success(let response):
                self.data = response.list.arrivalsAndDepartures
            }
        }

        return op
    }

    override func updateUI() {
        collectionController.reload(animated: false)
    }

    // MARK: - Actions

    @objc func cancel() {
        delegate?.bookmarkEditorCancelled(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
