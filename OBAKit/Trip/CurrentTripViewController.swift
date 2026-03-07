//
//  CurrentTripViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore
import CoreLocation

/// Finds and displays the user's current trip on a selected route.
///
/// After the user picks a route in `RoutePickerViewController`, this controller:
/// 1. Queries `NearbyTripMatcher` for nearby active vehicles on that route.
/// 2. If one match → navigates directly to `TripViewController`.
/// 3. If multiple → shows a disambiguation list.
/// 4. If none → shows an appropriate error state.
class CurrentTripViewController: UIViewController,
    AppContext,
    Idleable,
    OBAListViewDataSource {

    let application: Application

    private let route: Route
    private let listView = OBAListView()
    private lazy var dataLoadFeedbackGenerator = DataLoadFeedbackGenerator(application: application)

    /// Matching results found near the user.
    private var matchResults = [NearbyTripMatcher.MatchResult]()

    /// Current loading/error state.
    private enum State {
        case loading
        case noLocation
        case noResults
        case noRealtime
        case multipleResults
        case error(Error)
    }

    private var state: State = .loading

    // MARK: - Timer

    private static let refreshInterval: TimeInterval = 20.0
    private var refreshTimer: Timer?

    // MARK: - Init

    init(application: Application, route: Route) {
        self.application = application
        self.route = route
        super.init(nibName: nil, bundle: nil)

        title = OBALoc(
            "current_trip_controller.my_trip",
            value: "My Trip",
            comment: "Title for the current trip screen."
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        refreshTimer?.invalidate()
        findVehicleTask?.cancel()
    }

    // MARK: - UIViewController Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = ThemeColors.shared.systemBackground

        listView.obaDataSource = self
        view.addSubview(listView)
        listView.pinToSuperview(.edges)

        findVehicle()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        disableIdleTimer()
        startRefreshTimer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        enableIdleTimer()
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Idle Timer

    public var idleTimerFailsafe: Timer?

    // MARK: - Refresh Timer

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: Self.refreshInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            // Skip refresh when VoiceOver is active to avoid disrupting screen reader users.
            guard !UIAccessibility.isVoiceOverRunning else { return }
            self.findVehicle()
        }
    }

    // MARK: - Vehicle Finding

    private var findVehicleTask: Task<Void, Never>?

    private func findVehicle() {
        findVehicleTask?.cancel()

        findVehicleTask = Task { [weak self] in
            guard let self else { return }

            guard let userLocation = self.application.locationService.currentLocation else {
                await MainActor.run {
                    self.state = .noLocation
                    self.listView.applyData()
                }
                return
            }

            guard let apiService = self.application.apiService else {
                await MainActor.run {
                    self.state = .error(NearbyTripMatcher.MatchError.noStopsNearby)
                    self.listView.applyData()
                }
                return
            }

            let cachedStops = self.application.mapRegionManager.stops

            do {
                let results = try await NearbyTripMatcher.findTrips(
                    for: self.route,
                    near: userLocation,
                    using: apiService,
                    stops: cachedStops
                )

                if Task.isCancelled { return }

                await MainActor.run {
                    self.handleMatchResults(results)
                    self.dataLoadFeedbackGenerator.dataLoad(.success)
                }
            } catch is CancellationError {
                return
            } catch let error as NearbyTripMatcher.MatchError where error == .noRealtimeData {
                await MainActor.run {
                    self.state = .noRealtime
                    self.listView.applyData()
                    self.dataLoadFeedbackGenerator.dataLoad(.failed)
                }
            } catch {
                Logger.error("Failed to find trips: \(error)")
                await MainActor.run {
                    self.state = .error(error)
                    self.listView.applyData()
                    self.dataLoadFeedbackGenerator.dataLoad(.failed)
                }
            }
        }
    }

    private func handleMatchResults(_ results: [NearbyTripMatcher.MatchResult]) {
        matchResults = results

        switch results.count {
        case 0:
            state = .noResults
            listView.applyData()

        case 1:
            // Single match — navigate directly to TripViewController.
            let arrival = results[0].arrivalDeparture
            let tripController = TripViewController(application: application, arrivalDeparture: arrival)
            // Replace self in the navigation stack so back goes to the map, not this loading screen.
            if var viewControllers = navigationController?.viewControllers {
                viewControllers[viewControllers.count - 1] = tripController
                navigationController?.setViewControllers(viewControllers, animated: true)
            }

        default:
            state = .multipleResults
            listView.applyData()
        }
    }

    // MARK: - OBAListViewDataSource

    func items(for listView: OBAListView) -> [OBAListViewSection] {
        switch state {
        case .loading, .noLocation, .noResults, .noRealtime, .error:
            // Return empty — the empty state view is provided by emptyData(for:).
            return []

        case .multipleResults:
            return multipleResultsSections()
        }
    }

    func emptyData(for listView: OBAListView) -> OBAListView.EmptyData? {
        switch state {
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
        let rows: [AnyOBAListViewItem] = matchResults.map { result in
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
        self?.findVehicle()
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
