//
//  ReportProblemViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// The 'hub' view controller for reporting problems about stops and trips.
///
/// From here, a user can report incorrect stop details or a problem with a specific
/// trip's service. These reports are sent to the transit agency to improve data and
/// service — they are not app bug reports.
///
/// - Note: This view controller expects to be presented modally.
class ReportProblemViewController: TaskController<StopArrivals>,
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
    override func loadData() async throws -> StopArrivals {
        guard let apiService = application.apiService else {
            throw UnstructuredError("")
        }

        ProgressHUD.show()
        defer {
            Task { @MainActor in
                ProgressHUD.dismiss()
            }
        }

        return try await apiService.getArrivalsAndDeparturesForStop(id: stop.id, minutesBefore: 30, minutesAfter: 30).entry
    }

    @MainActor
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
            self?.showStopProblemForm()
        }

        return OBAListViewSection(id: "stop_problem_section", title: ReportProblemCopy.stopProblemHeader, contents: [row])
    }

    private var vehicleProblemSection: OBAListViewSection? {
        guard let arrivalsAndDepartures = data?.arrivalsAndDepartures, arrivalsAndDepartures.count > 0 else {
            return nil
        }

        let rows = arrivalsAndDepartures.map { ArrivalDepartureItem(arrivalDeparture: $0, isAlarmAvailable: false, onSelectAction: onSelectArrivalDeparture) }

        return OBAListViewSection(id: "vehicle_problem_section", title: ReportProblemCopy.vehicleProblemHeader, contents: rows)
    }

    func onSelectArrivalDeparture(_ arrivalDepartureItem: ArrivalDepartureItem) {
        guard let arrDep = data?.arrivalsAndDepartures.first(where: { $0.id == arrivalDepartureItem.arrivalDepartureID }) else { return }
        showVehicleProblemForm(for: arrDep)
    }

    // MARK: - Problem Forms

    private func showStopProblemForm() {
        let pageURL = "app://localhost/stop-problem"
        application.analytics?.reportEvent(pageURL: pageURL, label: AnalyticsLabels.reportProblem, value: "feedback_stop_problem")

        let stopID = stop.id
        let form = StopProblemView(
            send: { [weak self] code, comment, shareLocation in
                guard let self, let apiService = self.application.apiService else {
                    throw UnstructuredError("No API Service")
                }
                let location = shareLocation ? self.application.locationService.currentLocation : nil
                let report = RESTAPIService.StopProblemReport(stopID: stopID, code: code, comment: comment, location: location)
                _ = try await self.classifyingErrors { try await apiService.getStopProblem(report: report) }
                self.application.analytics?.reportEvent(pageURL: pageURL, label: AnalyticsLabels.reportProblem, value: "Reported Stop Problem")
            },
            onSent: { [weak self] in self?.finishReporting() }
        )

        pushProblemForm(form, title: OBALoc("stop_problem_controller.title", value: "Report a Problem", comment: "Title for the Report Stop Problem controller"))
    }

    private func showVehicleProblemForm(for arrivalDeparture: ArrivalDeparture) {
        let pageURL = "app://localhost/vehicle-problem"
        application.analytics?.reportEvent(pageURL: pageURL, label: AnalyticsLabels.reportProblem, value: "feedback_trip_problem")

        let (tripID, serviceDate, stopID) = (arrivalDeparture.tripID, arrivalDeparture.serviceDate, arrivalDeparture.stopID)
        let form = VehicleProblemView(
            vehicleID: arrivalDeparture.vehicleID,
            send: { [weak self] input in
                guard let self, let apiService = self.application.apiService else {
                    throw UnstructuredError("No API Service")
                }
                let report = RESTAPIService.TripProblemReport(
                    tripID: tripID,
                    serviceDate: serviceDate,
                    vehicleID: input.vehicleID,
                    stopID: stopID,
                    code: input.code,
                    comment: input.comment,
                    userOnVehicle: input.isOnVehicle,
                    location: input.shareLocation ? self.application.locationService.currentLocation : nil
                )
                _ = try await self.classifyingErrors { try await apiService.getTripProblem(report: report) }
                self.application.analytics?.reportEvent(pageURL: pageURL, label: AnalyticsLabels.reportProblem, value: "Reported Trip Problem")
            },
            onSent: { [weak self] in self?.finishReporting() }
        )

        pushProblemForm(form, title: OBALoc("vehicle_problem_controller.title", value: "Report a Problem", comment: "Title for the Report Vehicle Problem controller"))
    }

    private func pushProblemForm(_ form: some View, title: String) {
        let host = UIHostingController(rootView: form.defaultAppStorage(application.userDefaults))
        host.title = title
        navigationController?.pushViewController(host, animated: true)
    }

    /// Runs `body`, rethrowing any failure in its rider-facing form — with this
    /// region's name in server-down copy, and cellular restriction recognized.
    private func classifyingErrors<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            throw ErrorClassifier.classify(error, regionName: application.currentRegionName, isCellularDataRestricted: application.isCellularDataRestricted)
        }
    }

    /// A report went through: confirm it and close the whole report flow.
    private func finishReporting() {
        ProgressHUD.showSuccessAndDismiss()
        dismiss(animated: true)
    }

    // MARK: - Actions

    @objc private func cancel() {
        dismiss(animated: true, completion: nil)
    }
}
