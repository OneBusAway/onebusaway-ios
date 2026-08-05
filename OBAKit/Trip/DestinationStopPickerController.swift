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
        didSelectStop stopTime: TripStopTime
    )

    /// Called when the trip has no stops after the boarding stop and the user
    /// chooses to share without a destination instead.
    func destinationStopPickerDidSkipDestination(_ controller: DestinationStopPickerController)

    func destinationStopPickerDidCancel(_ controller: DestinationStopPickerController)
}

// MARK: - Controller

/// Presents a list of stops along a trip so the user can select their destination before sharing.
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/449
@MainActor
class DestinationStopPickerController: UIViewController, AppContext, OBAListViewDataSource {

    let application: Application

    let arrivalDeparture: ArrivalDeparture

    weak var delegate: DestinationStopPickerDelegate?

    // MARK: - State

    private enum State {
        case loading
        case empty
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
        // Cancel before any early return: if the service guard below fails, a
        // prior in-flight fetch must not survive to overwrite the `.error` state.
        fetchTask?.cancel()

        guard let apiService = application.apiService else {
            let error = NSError(
                domain: "DestinationStopPickerController",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: OBALoc(
                    "destination_stop_picker.error_no_service",
                    value: "Unable to connect to the transit service.",
                    comment: "Error shown when the API service is unavailable in the destination stop picker."
                )]
            )
            Logger.error("API service unavailable in DestinationStopPickerController for trip \(arrivalDeparture.tripID).")
            state = .error(error)
            return
        }

        state = .loading

        // Capture what the request needs up front rather than binding `self`
        // strongly across the await — otherwise the in-flight request keeps the
        // controller alive and `deinit`'s `fetchTask?.cancel()` can never run.
        let tripID = arrivalDeparture.tripID
        let vehicleID = arrivalDeparture.vehicleID
        let serviceDate = arrivalDeparture.serviceDate
        let boardingStopID = arrivalDeparture.stopID
        let boardingSequence = arrivalDeparture.stopSequence

        fetchTask = Task { [weak self] in
            do {
                let response = try await apiService.getTrip(
                    tripID: tripID,
                    vehicleID: vehicleID,
                    serviceDate: serviceDate
                )

                // A cancelled task (retry or dismissal) must not overwrite
                // state that a newer load may have already set.
                guard let self, !Task.isCancelled else { return }
                self.applyLoadedStopTimes(
                    response.entry.stopTimes,
                    boardingStopID: boardingStopID,
                    boardingSequence: boardingSequence,
                    tripID: tripID
                )
            } catch {
                // `isCancellation` also matches URLError.cancelled, which is how
                // URLSession reports a cancelled request — a plain
                // `is CancellationError` check misses it. Same shape as
                // TripViewModel.loadData().
                if Task.isCancelled || error.isCancellation { return }
                guard let self else { return }
                Logger.error("Failed to load trip \(tripID) stop times: \(error)")
                self.state = .error(
                    ErrorClassifier.classify(error, regionName: self.application.currentRegion?.name)
                )
            }
        }
    }

    /// Filters `allStopTimes` down to the stops after the boarding stop and
    /// transitions to the matching state.
    ///
    /// The boarding stop is located by `boardingSequence`
    /// (`ArrivalDeparture.stopSequence`, the index of the stop within the trip's
    /// stop sequence) rather than by searching for `boardingStopID`: on a loop
    /// trip that visits the same stop twice, an ID search matches the first
    /// occurrence and would offer stops the rider has already passed. The stopID
    /// cross-check fails closed to `.error` if the sequence and the stop list
    /// disagree — showing every stop instead would let the user share a
    /// destination that is behind them.
    private func applyLoadedStopTimes(_ allStopTimes: [TripStopTime], boardingStopID: StopID, boardingSequence: Int, tripID: String) {
        guard boardingSequence >= 0,
              boardingSequence < allStopTimes.count,
              allStopTimes[boardingSequence].stopID == boardingStopID else {
            let error = NSError(
                domain: "DestinationStopPickerController",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: OBALoc(
                    "destination_stop_picker.error_boarding_stop_not_found",
                    value: "Couldn't determine your boarding point on this trip.",
                    comment: "Error shown when the boarding stop cannot be found in the trip's stop list."
                )]
            )
            Logger.error("Boarding stop \(boardingStopID) at sequence \(boardingSequence) not found in trip \(tripID) stop times (count: \(allStopTimes.count)).")
            state = .error(error)
            return
        }

        let forwardStops = Array(allStopTimes.suffix(from: allStopTimes.index(after: boardingSequence)))
        state = forwardStops.isEmpty ? .empty : .data(forwardStops)
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        delegate?.destinationStopPickerDidCancel(self)
    }

    // MARK: - UI

    private let listView = OBAListView()

    // MARK: - OBAListViewDataSource

    func items(for listView: OBAListView) -> [OBAListViewSection] {
        guard case .data(let stopTimes) = state else {
            return []
        }

        let items: [AnyOBAListViewItem] = stopTimes.map { stopTime in
            let timeString = application.formatters.timeFormatter.string(from: stopTime.arrivalDate)

            let action: OBAListViewAction<OBAListRowView.ValueViewModel> = { [weak self] _ in
                guard let self else { return }
                self.delegate?.destinationStopPicker(self, didSelectStop: stopTime)
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
            return .standard(loadingViewModel)
        case .empty:
            return .standard(emptyViewModel)
        case .error(let error):
            return .standard(errorViewModel(for: error))
        case .data:
            return nil
        }
    }

    private var loadingViewModel: OBAListView.StandardEmptyDataViewModel {
        .init(
            title: OBALoc(
                "destination_stop_picker.loading_title",
                value: "Loading Stops",
                comment: "Title shown while loading the list of stops for destination selection."
            ),
            body: nil
        )
    }

    private var emptyViewModel: OBAListView.StandardEmptyDataViewModel {
        // Without this button the empty state would be a dead end: the
        // only exit is Cancel, with no way to share the trip at all.
        let shareConfig = ActivityIndicatedButton.Configuration(
            text: OBALoc(
                "destination_stop_picker.share_without_destination_button",
                value: "Share Without Destination",
                comment: "Button shown when a trip has no remaining stops, letting the user share the trip without picking a destination."
            ),
            largeContentImage: nil,
            showsActivityIndicatorOnTap: false,
            action: { [weak self] in
                guard let self else { return }
                self.delegate?.destinationStopPickerDidSkipDestination(self)
            }
        )
        return .init(
            title: OBALoc(
                "destination_stop_picker.no_stops_title",
                value: "No Stops Available",
                comment: "Title shown when there are no stops available after the boarding stop."
            ),
            body: OBALoc(
                "destination_stop_picker.no_stops_body",
                value: "There are no remaining stops on this trip.",
                comment: "Body text shown when there are no stops available after the boarding stop."
            ),
            buttonConfig: shareConfig
        )
    }

    private func errorViewModel(for error: Error) -> OBAListView.StandardEmptyDataViewModel {
        let retryConfig = ActivityIndicatedButton.Configuration(
            text: OBALoc(
                "destination_stop_picker.retry_button",
                value: "Try Again",
                comment: "Button to retry loading stops after an error."
            ),
            largeContentImage: nil,
            showsActivityIndicatorOnTap: true,
            action: { [weak self] in self?.loadStopTimes() }
        )
        return .init(error: error, buttonConfig: retryConfig)
    }
}
