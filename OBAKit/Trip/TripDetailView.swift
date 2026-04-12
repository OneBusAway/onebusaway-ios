//
//  TripDetailView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

// MARK: - TripDetailViewModel

/// Observable view model that bridges `TripViewController`'s data loading
/// into the SwiftUI `TripDetailView`.
@MainActor
final class TripDetailViewModel: ObservableObject {
    @Published var tripDetails: TripDetails?
    @Published var tripConvertible: TripConvertible

    /// Called when the user taps a stop row — used to pan the map to that stop.
    var onStopSelected: ((TripStopTime) -> Void)?

    /// The view controller hosting this view model. Required for navigation.
    weak var hostViewController: UIViewController?

    private let application: Application

    init(application: Application, tripConvertible: TripConvertible) {
        self.application = application
        self.tripConvertible = tripConvertible
    }

    /// Triggers a data reload from the API. Called by `TripViewController` after
    /// refreshing `tripConvertible`.
    func loadData() {
        // Data loading is driven by TripViewController; this method exists as a
        // hook so the VC can signal the VM to re-publish after updating tripConvertible.
        objectWillChange.send()
    }

    // MARK: - Derived display data

    var headerViewModel: TripPanelHeaderViewModel? {
        guard let arrDep = tripConvertible.arrivalDeparture else { return nil }
        return TripPanelHeaderViewModel(arrivalDeparture: arrDep, formatters: application.formatters)
    }

    var stopViewModels: [TripStopRowViewModel] {
        guard let details = tripDetails else { return [] }
        return TripStopRowViewModel.viewModels(
            from: details,
            arrivalDeparture: tripConvertible.arrivalDeparture,
            formatters: application.formatters,
            onSelect: { [weak self] _ in }
        )
    }

    func selectStop(_ viewModel: TripStopRowViewModel) {
        guard let details = tripDetails,
              let stopTime = details.stopTimes.first(where: { $0.stopID == viewModel.id }),
              let hostVC = hostViewController
        else { return }

        let transferContext = buildTransferContext(for: stopTime)
        application.viewRouter.navigateTo(stop: stopTime.stop, from: hostVC, transferContext: transferContext)
    }

    // MARK: - Helpers

    private func buildTransferContext(for stopTime: TripStopTime) -> TransferContext? {
        guard let arrivalDeparture = tripConvertible.arrivalDeparture else { return nil }
        // Don't offer a transfer context for the user's own boarding stop
        guard stopTime.stopID != arrivalDeparture.stopID else { return nil }
        return .from(arrivalDeparture: arrivalDeparture, arrivalDate: stopTime.arrivalDate)
    }
}

// MARK: - TripDetailView

/// SwiftUI view used as the floating panel content inside `TripViewController`.
/// Wraps `TripStopListView` and drives it from `TripDetailViewModel`.
struct TripDetailView: View {
    @ObservedObject var viewModel: TripDetailViewModel

    var body: some View {
        if let header = viewModel.headerViewModel {
            TripStopListView(
                header: header,
                stops: viewModel.stopViewModels,
                onSelectStop: { viewModel.selectStop($0) }
            )
        } else {
            // Minimal placeholder while data loads
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color(.tertiaryLabel))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                Spacer()
                ProgressView()
                Spacer()
            }
            .background(Color(.systemBackground))
        }
    }
}
