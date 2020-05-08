//
//  ReportProblemViewController.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 6/12/19.
//

import UIKit
import IGListKit
import OBAKitCore

/// The 'hub' view controller for reporting problems about stops and trips.
///
/// From here, a user can report a problem either about a `Stop` or about a trip at that stop.
///
/// - Note: This view controller expects to be presented modally.
class ReportProblemViewController: OperationController<DecodableOperation<RESTAPIResponse<StopArrivals>>, StopArrivals>,
    HasTableStyle,
    ListAdapterDataSource {

    private let stop: Stop

    // MARK: - Init

    /// This is the default initializer for `ReportProblemViewController`.
    /// - Parameter application: The application object
    /// - Parameter stop: The `Stop` object about which a problem is being reported. This will be used to load available `ArrivalDeparture` objects, as well.
    ///
    /// Initialize the view controller, wrap it with a navigation controller, and then modally present it to use.
    public init(application: Application, stop: Stop) {
        self.stop = stop

        super.init(application: application)

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))

        title = OBALoc("report_problem.title", value: "Report a Problem", comment: "Title of the Report Problem view controller.")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.groupedTableBackground

        addChildController(collectionController)
        collectionController.view.pinToSuperview(.edges)
    }

    // MARK: - Collection Controller

    private lazy var collectionController = CollectionController(application: application, dataSource: self, style: tableStyle)

    public let tableStyle = TableCollectionStyle.grouped

    // MARK: - OperationController

    override func loadData() -> DecodableOperation<RESTAPIResponse<StopArrivals>>? {
        guard let apiService = application.restAPIService else { return nil }

        SVProgressHUD.show()

        let op = apiService.getArrivalsAndDeparturesForStop(id: stop.id, minutesBefore: 30, minutesAfter: 30)
        op.complete { [weak self] result in
            SVProgressHUD.dismiss()

            guard let self = self else { return }

            switch result {
            case .failure(let error):
                print("TODO FIXME handle error! \(error)")
            case .success(let response):
                self.data = response.list
            }
        }
        return op
    }

    override func updateUI() {
        collectionController.reload(animated: false)
    }

    // MARK: - IGListKit

    public func objects(for listAdapter: ListAdapter) -> [ListDiffable] {
        var sections = [ListDiffable]()

        sections.append(contentsOf: stopProblemSection)

        if let vehicleProblemSections = vehicleProblemSections {
            sections.append(contentsOf: vehicleProblemSections)
        }

        return sections
    }

    public func listAdapter(_ listAdapter: ListAdapter, sectionControllerFor object: Any) -> ListSectionController {
        return defaultSectionController(for: object)
    }

    public func emptyView(for listAdapter: ListAdapter) -> UIView? {
        return nil
    }

    // MARK: - Data Sections

    private var stopProblemSection: [ListDiffable] {
        let fmt = OBALoc(
            "report_problem_controller.report_stop_problem_fmt",
            value: "Report a problem with the stop at %@",
            comment: "Report a problem with the stop at {Stop Name}"
        )

        let row = TableRowData(title: String(format: fmt, stop.name), accessoryType: .disclosureIndicator) { [weak self] _ in
            guard let self = self else { return }
            let stopProblemController = StopProblemViewController(application: self.application, stop: self.stop)
            self.navigationController?.pushViewController(stopProblemController, animated: true)
        }

        return [
            TableHeaderData(title: OBALoc("report_problem_controller.stop_problem.header", value: "Problem with the Stop", comment: "A table header in the 'Report Problem' view controller.")),
            TableSectionData(row: row)
        ]
    }

    private var vehicleProblemSections: [ListDiffable]? {
        guard let arrivalsAndDepartures = data?.arrivalsAndDepartures, arrivalsAndDepartures.count > 0 else {
            return nil
        }

        var rows: [ListDiffable] = [TableHeaderData(title: OBALoc("report_problem_controller.vehicle_problem.header", value: "Problem with a Vehicle at the Stop", comment: "A table header in the 'Report Problem' view controller."))]

        for arrDep in arrivalsAndDepartures {
            let row = ArrivalDepartureSectionData(arrivalDeparture: arrDep) { [weak self] in
                guard let self = self else { return }
                let controller = VehicleProblemViewController(application: self.application, arrivalDeparture: arrDep)
                self.navigationController?.pushViewController(controller, animated: true)
            }
            rows.append(row)
        }

        return rows
    }

    // MARK: - Actions

    @objc private func cancel() {
        dismiss(animated: true, completion: nil)
    }
}
