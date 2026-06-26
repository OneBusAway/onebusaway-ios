//
//  CurrentTripView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// SwiftUI surface for the "find my current trip on this route" flow. Pushed
/// onto the stacked sheet layer from `RoutePickerView`. Owns the UIKit-flavored
/// side effects the merged `CurrentTripViewModel` intentionally doesn't:
/// idle-timer ownership, haptic feedback, and the VoiceOver gate.
struct CurrentTripView: View {
    @StateObject private var viewModel: CurrentTripViewModel
    @EnvironmentObject var coordinator: SheetCoordinator<AppSheetRoute>
    @Environment(\.scenePhase) private var scenePhase

    let onPresentTrip: (ArrivalDeparture) -> Void

    @State private var wasIdleTimerDisabledByUs = false
    private let feedback: DataLoadFeedbackGenerator
    private let formatters: Formatters

    init(
        viewModel: @autoclosure @escaping () -> CurrentTripViewModel,
        feedback: DataLoadFeedbackGenerator,
        formatters: Formatters,
        onPresentTrip: @escaping (ArrivalDeparture) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.feedback = feedback
        self.formatters = formatters
        self.onPresentTrip = onPresentTrip
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(OBALoc(
                    "current_trip_controller.my_trip",
                    value: "My Trip",
                    comment: "Title for the current trip screen."
                )))
                .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            viewModel.shouldSkipProgrammaticRefresh = { UIAccessibility.isVoiceOverRunning }
            disableIdleTimer()
            viewModel.start()
        }
        .onDisappear {
            viewModel.deactivate()
            reEnableIdleTimer()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                viewModel.deactivate()
                reEnableIdleTimer()
            }
        }
        .onChange(of: viewModel.pendingNavigation) { _, arrival in
            guard let arrival else { return }
            feedback.dataLoad(.success)
            onPresentTrip(arrival)
            // Re-arm so a second single-match (e.g., user retries) can fire.
            viewModel.pendingNavigation = nil
        }
        .onChange(of: stateKey) { _, newKey in
            if newKey == .error || newKey == .noRealtime {
                feedback.dataLoad(.failed)
            }
        }
    }

    // MARK: - Idle Timer

    private func disableIdleTimer() {
        guard !UIApplication.shared.isIdleTimerDisabled else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        wasIdleTimerDisabledByUs = true
    }

    private func reEnableIdleTimer() {
        guard wasIdleTimerDisabledByUs else { return }
        UIApplication.shared.isIdleTimerDisabled = false
        wasIdleTimerDisabledByUs = false
    }

    // MARK: - State observation key
    //
    // `CurrentTripViewModel.State` carries an associated `Error` so it isn't
    // Equatable. Map to a small enum the `.onChange` modifier can compare.
    private enum StateKey: Equatable {
        case loading, noLocation, noResults, noRealtime, multipleResults, error
    }

    private var stateKey: StateKey {
        switch viewModel.state {
        case .loading:          return .loading
        case .noLocation:       return .noLocation
        case .noResults:        return .noResults
        case .noRealtime:       return .noRealtime
        case .multipleResults:  return .multipleResults
        case .error:            return .error
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ContentUnavailableView(
                OBALoc("current_trip_controller.detecting", value: "Finding your vehicle…", comment: "Loading message while searching for the user's vehicle."),
                systemImage: "location.viewfinder"
            )

        case .noLocation:
            ContentUnavailableView(
                OBALoc("current_trip_controller.location_unavailable", value: "Location unavailable. Please enable location services.", comment: "Error message when the user's location is not available."),
                systemImage: "location.slash"
            )

        case .noResults:
            ContentUnavailableView(label: {
                Label(
                    OBALoc("current_trip_controller.no_results", value: "No active vehicle found on this route near you", comment: "Message when no active vehicle is found near the user on the selected route."),
                    systemImage: "bus"
                )
            }, actions: { retryButton })

        case .noRealtime:
            ContentUnavailableView(
                OBALoc("current_trip_controller.no_realtime", value: "No real-time tracking available for this route", comment: "Message when the route has no real-time tracking data."),
                systemImage: "antenna.radiowaves.left.and.right.slash"
            )

        case .error(let error):
            ContentUnavailableView(label: {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
            }, actions: { retryButton })

        case .multipleResults:
            resultsList
        }
    }

    private var retryButton: some View {
        Button {
            viewModel.findVehicle()
        } label: {
            Label(
                OBALoc("current_trip_controller.retry", value: "Try Again", comment: "Button to retry finding the user's vehicle."),
                systemImage: "arrow.clockwise"
            )
        }
    }

    private var resultsList: some View {
        List {
            Section(
                header: Text(OBALoc(
                    "current_trip_controller.multiple_vehicles",
                    value: "Multiple vehicles found",
                    comment: "Section header when multiple vehicles are found on the selected route."
                ))
            ) {
                ForEach(viewModel.matchResults, id: \.arrivalDeparture.tripID) { result in
                    Button {
                        onPresentTrip(result.arrivalDeparture)
                    } label: {
                        resultRow(result)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func resultRow(_ result: NearbyTripMatcher.MatchResult) -> some View {
        // Subtitle preserves the UIKit empty-vehicleID branch from
        // CurrentTripViewController.swift:289-290.
        let arrival = result.arrivalDeparture
        let distance = formatters.distanceFormatter.string(fromDistance: result.distanceFromUser)
        let distanceLabel = String(
            format: OBALoc(
                "current_trip_controller.distance_fmt",
                value: "%@ away",
                comment: "Distance from user to vehicle. e.g. '0.2 mi away'"
            ),
            distance
        )
        let vehicleID = arrival.vehicleID ?? ""
        let subtitle = vehicleID.isEmpty ? distanceLabel : "\(vehicleID) · \(distanceLabel)"

        VStack(alignment: .leading, spacing: 2) {
            Text(arrival.routeAndHeadsign)
                .font(.body)
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
