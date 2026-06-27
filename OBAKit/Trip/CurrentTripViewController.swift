//
//  CurrentTripViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import Combine
import OBAKitCore

/// Finds and displays the user's current trip on a selected route.
///
/// After the user picks a route in `RoutePickerViewController`, this controller:
/// 1. Asks `CurrentTripViewModel` to query nearby active vehicles on that route.
/// 2. If one match → navigates directly to `TripViewController`.
/// 3. If multiple → shows a disambiguation list.
/// 4. If none → shows an appropriate error state.
class CurrentTripViewController: UIViewController,
    AppContext,
    Idleable,
    OBAListViewDataSource {

    let application: Application

    private let viewModel: CurrentTripViewModel
    private let listView = OBAListView()
    private lazy var dataLoadFeedbackGenerator = DataLoadFeedbackGenerator(application: application)
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(application: Application, route: Route) {
        self.application = application
        self.viewModel = CurrentTripViewModel(application: application, route: route)
        super.init(nibName: nil, bundle: nil)

        title = OBALoc(
            "current_trip_controller.my_trip",
            value: "My Trip",
            comment: "Title for the current trip screen."
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - UIViewController Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground

        listView.obaDataSource = self
        view.addSubview(listView)
        listView.pinToSuperview(.edges)

        viewModel.shouldSkipProgrammaticRefresh = { UIAccessibility.isVoiceOverRunning }
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        disableIdleTimer()
        viewModel.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        enableIdleTimer()
        viewModel.deactivate()
    }

    // MARK: - Idle Timer

    public var idleTimerFailsafe: Timer?

    // MARK: - View Model Binding

    private func bindViewModel() {
        viewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.listView.applyData()
                switch state {
                case .loading, .noLocation:
                    break
                case .noResults, .multipleResults:
                    // Matcher returned (possibly empty) — treat as a successful fetch.
                    self.dataLoadFeedbackGenerator.dataLoad(.success)
                case .noRealtime, .error:
                    self.dataLoadFeedbackGenerator.dataLoad(.failed)
                }
            }
            .store(in: &cancellables)

        viewModel.$pendingNavigation
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] arrival in
                guard let self else { return }
                guard let nav = self.navigationController else {
                    self.viewModel.pendingNavigationUnavailable()
                    return
                }
                self.dataLoadFeedbackGenerator.dataLoad(.success)
                let tripController = TripViewController(application: self.application, arrivalDeparture: arrival)
                var stack = nav.viewControllers
                stack[stack.count - 1] = tripController
                nav.setViewControllers(stack, animated: true)
                self.viewModel.pendingNavigation = nil
            }
            .store(in: &cancellables)
    }

    // MARK: - OBAListViewDataSource

    func items(for listView: OBAListView) -> [OBAListViewSection] {
        switch viewModel.state {
        case .loading, .noLocation, .noResults, .noRealtime, .error:
            return []

        case .multipleResults:
            return multipleResultsSections()
        }
    }

    func emptyData(for listView: OBAListView) -> OBAListView.EmptyData? {
        switch viewModel.state {
        case .loading:
            return .standard(.init(
                alignment: .center,
                title: loadingTitle,
                body: nil
            ))

        case .noLocation:
            return .standard(.init(
                alignment: .center,
                title: noLocationTitle,
                body: nil
            ))

        case .noResults:
            return .standard(.init(
                alignment: .center,
                title: noResultsTitle,
                body: nil,
                buttonConfig: retryButtonConfig
            ))

        case .noRealtime:
            return .standard(.init(
                alignment: .center,
                title: noRealtimeTitle,
                body: nil
            ))

        case .error(let error):
            return .standard(.init(
                alignment: .center,
                title: error.localizedDescription,
                body: nil,
                buttonConfig: retryButtonConfig
            ))

        case .multipleResults:
            return nil
        }
    }

    private func multipleResultsSections() -> [OBAListViewSection] {
        let rows: [AnyOBAListViewItem] = viewModel.matchResults.map { result in
            let arrival = result.arrivalDeparture
            let formattedDistance = application.formatters.distanceFormatter.string(fromDistance: result.distanceFromUser)
            let headsign = arrival.routeAndHeadsign

            let distanceLabel = String(
                format: OBALoc(
                    "current_trip_controller.distance_fmt",
                    value: "%@ away",
                    comment: "Distance from user to vehicle. e.g. '0.2 mi away'"
                ),
                formattedDistance
            )

            let vehicleID = arrival.vehicleID ?? ""
            let subtitle = vehicleID.isEmpty ? distanceLabel : "\(vehicleID) · \(distanceLabel)"

            return OBAListRowView.SubtitleViewModel(
                title: headsign,
                subtitle: subtitle,
                accessoryType: .disclosureIndicator
            ) { [weak self] _ in
                self?.didSelectResult(result)
            }.typeErased
        }

        let headerTitle = OBALoc(
            "current_trip_controller.multiple_vehicles",
            value: "Multiple vehicles found",
            comment: "Section header when multiple vehicles are found on the selected route."
        )

        return [OBAListViewSection(id: "trips", title: headerTitle, contents: rows)]
    }

    private func didSelectResult(_ result: NearbyTripMatcher.MatchResult) {
        let tripController = TripViewController(application: application, arrivalDeparture: result.arrivalDeparture)
        application.viewRouter.navigate(to: tripController, from: self)
    }

    // MARK: - Retry

    private lazy var retryButtonConfig = ActivityIndicatedButton.Configuration(
        text: OBALoc(
            "current_trip_controller.retry",
            value: "Try Again",
            comment: "Button to retry finding the user's vehicle."
        ),
        largeContentImage: Icons.refresh,
        showsActivityIndicatorOnTap: true
    ) { [weak self] in
        self?.viewModel.findVehicle()
    }

    // MARK: - Localized Strings

    private var loadingTitle: String {
        OBALoc(
            "current_trip_controller.detecting",
            value: "Finding your vehicle…",
            comment: "Loading message while searching for the user's vehicle."
        )
    }

    private var noLocationTitle: String {
        OBALoc(
            "current_trip_controller.location_unavailable",
            value: "Location unavailable. Please enable location services.",
            comment: "Error message when the user's location is not available."
        )
    }

    private var noResultsTitle: String {
        OBALoc(
            "current_trip_controller.no_results",
            value: "No active vehicle found on this route near you",
            comment: "Message when no active vehicle is found near the user on the selected route."
        )
    }

    private var noRealtimeTitle: String {
        OBALoc(
            "current_trip_controller.no_realtime",
            value: "No real-time tracking available for this route",
            comment: "Message when the route has no real-time tracking data."
        )
    }
}
