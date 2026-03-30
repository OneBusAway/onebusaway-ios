//
//  DestinationStopPickerController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

// MARK: - Delegate

protocol DestinationStopPickerDelegate: AnyObject {
    func destinationStopPicker(
        _ controller: DestinationStopPickerController,
        didSelectStop stopTime: TripStopTime,
        for arrivalDeparture: ArrivalDeparture
    )
    func destinationStopPickerDidCancel(_ controller: DestinationStopPickerController)
}

// MARK: - Controller

/// Presents a list of stops along a trip so the user can select their destination before sharing.
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/449
class DestinationStopPickerController: UIViewController, AppContext, OBAListViewDataSource {

    let application: Application

    private let arrivalDeparture: ArrivalDeparture

    weak var delegate: DestinationStopPickerDelegate?

    // MARK: - State

    private enum State {
        case loading
        case data([TripStopTime])
        case error(Error)
    }

    private var state: State = .loading {
        didSet {
            guard isViewLoaded else { return }
            listView.applyData(animated: false)
        }
    }

    private var fetchTask: Task<Void, Never>?

    // MARK: - Init/Deinit

    init(application: Application, arrivalDeparture: ArrivalDeparture) {
        self.application = application
        self.arrivalDeparture = arrivalDeparture
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        fetchTask?.cancel()
    }

    // MARK: - UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OBALoc(
            "destination_stop_picker.title",
            value: "Select Destination",
            comment: "Navigation bar title for the destination stop picker when sharing a trip."
        )

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        view.backgroundColor = ThemeColors.shared.systemBackground

        listView.formatters = application.formatters
        listView.obaDataSource = self
        view.addSubview(listView)
        listView.pinToSuperview(.edges)

        loadStopTimes()
    }

    // MARK: - Data Loading

    private func loadStopTimes() {
        guard let apiService = application.apiService else {
            state = .error(APIError.noResponseBody)
            Logger.error("API service unavailable in DestinationStopPickerController.")
            return
        }

        fetchTask = Task { [weak self] in
            guard let self else { return }

            do {
                let response = try await apiService.getTrip(
                    tripID: self.arrivalDeparture.tripID,
                    vehicleID: self.arrivalDeparture.vehicleID,
                    serviceDate: self.arrivalDeparture.serviceDate
                )

                let allStopTimes = response.entry.stopTimes
                let boardingStopID = self.arrivalDeparture.stopID

                // Only show stops after the boarding stop.
                let boardingIndex = allStopTimes.firstIndex { $0.stopID == boardingStopID }
                let forwardStops: [TripStopTime]
                if let boardingIndex {
                    forwardStops = Array(allStopTimes.suffix(from: allStopTimes.index(after: boardingIndex)))
                } else {
                    Logger.warn("Boarding stop \(boardingStopID) not found in trip stop times; showing all stops.")
                    forwardStops = allStopTimes
                }

                await MainActor.run {
                    self.state = .data(forwardStops)
                }
            } catch {
                if error is CancellationError { return }
                Logger.error("Failed to load trip stop times: \(error)")
                await MainActor.run {
                    self.state = .error(
                        ErrorClassifier.classify(error, regionName: self.application.currentRegion?.name)
                    )
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        delegate?.destinationStopPickerDidCancel(self)
    }

    // MARK: - UI

    private let listView = OBAListView()

    // MARK: - OBAListViewDataSource

    func items(for listView: OBAListView) -> [OBAListViewSection] {
        guard case .data(let stopTimes) = state, !stopTimes.isEmpty else {
            return []
        }

        let items: [AnyOBAListViewItem] = stopTimes.map { stopTime in
            let timeString = application.formatters.timeFormatter.string(from: stopTime.arrivalDate)

            let action: OBAListViewAction<OBAListRowView.ValueViewModel> = { [weak self] _ in
                guard let self else { return }
                self.delegate?.destinationStopPicker(self, didSelectStop: stopTime, for: self.arrivalDeparture)
            }

            return OBAListRowView.ValueViewModel(
                title: stopTime.stop.name,
                subtitle: timeString,
                accessoryType: .disclosureIndicator,
                onSelectAction: action
            ).typeErased
        }

        let header = OBALoc(
            "destination_stop_picker.select_destination_header",
            value: "Where are you getting off?",
            comment: "Section header prompting user to select their destination stop."
        )

        return [OBAListViewSection(id: "destination_stops", title: header, contents: items)]
    }

    func emptyData(for listView: OBAListView) -> OBAListView.EmptyData? {
        switch state {
        case .loading:
            return .standard(.init(
                title: OBALoc(
                    "destination_stop_picker.loading_title",
                    value: "Loading Stops",
                    comment: "Title shown while loading the list of stops for destination selection."
                ),
                body: nil
            ))
        case .error(let error):
            return .standard(.init(error: error))
        case .data(let stops) where stops.isEmpty:
            return .standard(.init(
                title: OBALoc(
                    "destination_stop_picker.no_stops_title",
                    value: "No Stops Available",
                    comment: "Title shown when there are no stops available after the boarding stop."
                ),
                body: OBALoc(
                    "destination_stop_picker.no_stops_body",
                    value: "There are no remaining stops on this trip.",
                    comment: "Body text shown when there are no stops available after the boarding stop."
                )
            ))
        case .data:
            return nil
        }
    }
}
