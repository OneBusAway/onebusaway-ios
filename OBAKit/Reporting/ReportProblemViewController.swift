//
//  ReportProblemViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

/// The 'hub' view controller for reporting problems about stops and trips.
///
/// From here, a user can report a problem either about a `Stop` or about a trip at that stop.
///
/// - Note: This view controller expects to be presented modally.
class ReportProblemViewController: OperationController<DecodableOperation<RESTAPIResponse<StopArrivals>>, StopArrivals>,
    OBAListViewDataSource {

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

        listView.obaDataSource = self
        listView.formatters = application.formatters
        listView.register(listViewItem: ArrivalDepartureItem.self)

        view.addSubview(listView)
        listView.pinToSuperview(.edges)
    }

    // MARK: - Collection Controller
    let listView = OBAListView()

    // MARK: - OperationController

    override func loadData() -> DecodableOperation<RESTAPIResponse<StopArrivals>>? {
        guard let apiService = application.restAPIService else { return nil }

        ProgressHUD.show()

        let op = apiService.getArrivalsAndDeparturesForStop(id: stop.id, minutesBefore: 30, minutesAfter: 30)
        op.complete { [weak self] result in
            ProgressHUD.dismiss()

            guard let self = self else { return }

            switch result {
            case .failure(let error):
                self.application.displayError(error)
            case .success(let response):
                self.data = response.entry
            }
        }
        return op
    }

    override func updateUI() {
        listView.applyData()
    }

    // MARK: - IGListKit
    func items(for listView: OBAListView) -> [OBAListViewSection] {
        return [stopProblemSection, vehicleProblemSection].compactMap { $0 }
    }

    // MARK: - Data Sections

    private var stopProblemSection: OBAListViewSection {
        let fmt = OBALoc(
            "report_problem_controller.report_stop_problem_fmt",
            value: "Report a problem with the stop at %@",
            comment: "Report a problem with the stop at {Stop Name}"
        )

        let row = OBAListRowView.DefaultViewModel(title: String(format: fmt, stop.name), accessoryType: .disclosureIndicator) { [weak self] _ in
            guard let self = self else { return }
            let stopProblemController = StopProblemViewController(application: self.application, stop: self.stop)
            self.navigationController?.pushViewController(stopProblemController, animated: true)
        }

        return OBAListViewSection(id: "stop_problem_section", title: OBALoc("report_problem_controller.stop_problem.header", value: "Problem with the Stop", comment: "A table header in the 'Report Problem' view controller."), contents: [row])
    }

    private var vehicleProblemSection: OBAListViewSection? {
        guard let arrivalsAndDepartures = data?.arrivalsAndDepartures, arrivalsAndDepartures.count > 0 else {
            return nil
        }

        let rows = arrivalsAndDepartures.map { ArrivalDepartureItem(arrivalDeparture: $0, isAlarmAvailable: false, isDeepLinkingAvailable: false, onSelectAction: onSelectArrivalDeparture) }

        return OBAListViewSection(id: "vehicle_problem_section", title: OBALoc("report_problem_controller.vehicle_problem.header", value: "Problem with a Vehicle at the Stop", comment: "A table header in the 'Report Problem' view controller."), contents: rows.uniqued)
    }

    func onSelectArrivalDeparture(_ arrivalDepartureItem: ArrivalDepartureItem) {
        guard let arrDep = data?.arrivalsAndDepartures.first(where: { $0.id == arrivalDepartureItem.identifier }) else { return }
        let controller = VehicleProblemViewController(application: self.application, arrivalDeparture: arrDep)
        self.navigationController?.pushViewController(controller, animated: true)
    }

    // MARK: - Actions

    @objc private func cancel() {
        dismiss(animated: true, completion: nil)
    }
}
