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
                .navigationTitle(Text(Strings.currentTripTitle))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(Strings.close) { coordinator.pop() }
                    }
                }
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
        .onChange(of: scenePhase) { previous, phase in
            switch phase {
            case .active:
                // Only re-arm on the .background → .active edge. `.inactive → .active`
                // (returning from Control Center / a banner / a system alert) never
                // stopped the timer, so re-arming would issue a redundant network call.
                if previous == .background {
                    disableIdleTimer()
                    viewModel.start()
                }
            case .background:
                viewModel.deactivate()
                reEnableIdleTimer()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onChange(of: viewModel.pendingNavigation) { _, arrival in
            guard let arrival else { return }
            feedback.dataLoad(.success)
            onPresentTrip(arrival)
            // Re-arm so a second single-match (e.g., user retries) can fire.
            viewModel.pendingNavigation = nil
        }
        .onChange(of: viewModel.state) { _, newState in
            // Pattern-match because `.error` carries an associated value —
            // `newState == .error` would need a payload to compare against.
            switch newState {
            case .error, .noRealtime:
                feedback.dataLoad(.failed)
            default:
                break
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

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            EmptyStateView(title: Strings.currentTripFindingVehicle, systemImage: AppSymbol.locationFinding)
        case .noLocation:
            EmptyStateView(title: Strings.currentTripLocationUnavailable, systemImage: AppSymbol.locationUnavailable)
        case .noResults:
            EmptyStateView(title: Strings.currentTripNoActiveVehicle, systemImage: AppSymbol.bus) { retryButton }
        case .noRealtime:
            EmptyStateView(title: Strings.currentTripNoRealtime, systemImage: AppSymbol.noRealtime)
        case .error(let error):
            EmptyStateView(title: error.localizedDescription, systemImage: AppSymbol.error) { retryButton }
        case .multipleResults:
            resultsList
        }
    }

    private var retryButton: some View {
        Button {
            viewModel.findVehicle()
        } label: {
            Label(Strings.currentTripTryAgain, systemImage: AppSymbol.retry)
        }
    }

    private var resultsList: some View {
        List {
            Section(header: Text(Strings.currentTripMultipleVehicles)) {
                ForEach(viewModel.matchResults, id: \.arrivalDeparture.tripID) { result in
                    Button {
                        onPresentTrip(result.arrivalDeparture)
                    } label: {
                        resultRow(result)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func resultRow(_ result: NearbyTripMatcher.MatchResult) -> some View {
        let arrival = result.arrivalDeparture
        let distance = formatters.distanceFormatter.string(fromDistance: result.distanceFromUser)
        let distanceLabel = String(format: Strings.currentTripDistanceFormat, distance)
        let vehicleID = arrival.vehicleID ?? ""
        let subtitle = vehicleID.isEmpty ? distanceLabel : "\(vehicleID) · \(distanceLabel)"

        VStack(alignment: .leading, spacing: 2) {
            Text(arrival.routeAndHeadsign)
                .font(.body)
                .foregroundStyle(Color(ThemeColors.shared.label))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Color(ThemeColors.shared.secondaryLabel))
        }
        .accessibilityElement(children: .combine)
    }
}
