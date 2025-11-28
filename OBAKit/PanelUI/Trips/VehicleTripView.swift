//
//  VehicleTripView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// SwiftUI view displaying trip details with a stop timeline, similar to TripFloatingPanelController
struct VehicleTripView: View {
    @ObservedObject var coordinator: TripDisplayCoordinator
    var onNavigateToStop: ((Stop) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Header with trip info and close button
            tripHeader

            Divider()

            // Content area
            if coordinator.isLoadingTrip {
                loadingView
            } else if let error = coordinator.tripLoadError {
                errorView(error)
            } else if let tripDetails = coordinator.tripDetails {
                tripContent(tripDetails)
            } else {
                emptyView
            }
        }
    }

    // MARK: - Header

    private var tripHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if let tripDetails = coordinator.tripDetails {
                    // Route name and headsign
                    HStack(spacing: 8) {
                        if let routeShortName = tripDetails.trip?.route?.shortName {
                            Text(routeShortName)
                                .font(.headline)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(coordinator.routeColor)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        Text(tripDetails.trip?.routeHeadsign ?? "Trip Details")
                            .font(.headline)
                            .lineLimit(1)
                    }

                    // Vehicle info and last update
                    HStack(spacing: 8) {
                        if let vehicleID = tripDetails.status?.vehicleID {
                            Label(vehicleID, systemImage: "bus.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let lastUpdate = tripDetails.status?.lastUpdate {
                            Label(
                                coordinator.application.formatters.timeAgoInWords(date: lastUpdate),
                                systemImage: "clock"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Loading trip...")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Close button
            Button {
                coordinator.dismissTrip()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Close trip view")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Content Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading trip details...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("Unable to load trip")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                if let arrDep = coordinator.selectedArrivalDeparture {
                    Task {
                        await coordinator.selectArrivalDeparture(arrDep)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bus")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No trip data available")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private func tripContent(_ tripDetails: TripDetails) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Previous trip (if available)
                if let previousTrip = tripDetails.previousTrip {
                    AdjacentTripRow(trip: previousTrip, order: .previous) {
                        Task {
                            await coordinator.navigateToAdjacentTrip(previousTrip)
                        }
                    }
                    Divider()
                        .padding(.leading, 60)
                }

                // Stop timeline
                ForEach(Array(tripDetails.stopTimes.enumerated()), id: \.element.stopID) { index, stopTime in
                    TripStopRow(
                        stopTime: stopTime,
                        isUserDestination: stopTime.stopID == coordinator.userDestinationStopID,
                        isCurrentVehicleLocation: stopTime.stopID == coordinator.currentVehicleStopID,
                        routeType: tripDetails.trip?.route?.routeType ?? .bus,
                        formatters: coordinator.application.formatters,
                        isFirst: index == 0 && tripDetails.previousTrip == nil,
                        isLast: index == tripDetails.stopTimes.count - 1 && tripDetails.nextTrip == nil
                    ) {
                        onNavigateToStop?(stopTime.stop)
                    }

                    if index < tripDetails.stopTimes.count - 1 || tripDetails.nextTrip != nil {
                        Divider()
                            .padding(.leading, 60)
                    }
                }

                // Next trip (if available)
                if let nextTrip = tripDetails.nextTrip {
                    Divider()
                        .padding(.leading, 60)
                    AdjacentTripRow(trip: nextTrip, order: .next) {
                        Task {
                            await coordinator.navigateToAdjacentTrip(nextTrip)
                        }
                    }
                }
            }
        }
    }
}

#if DEBUG
struct VehicleTripView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.3)
                .ignoresSafeArea()

            VStack {
                Spacer()

                // Preview placeholder - would need mock coordinator
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 36, height: 5)
                        .padding(.vertical, 8)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text("10")
                                    .font(.headline)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))

                                Text("Capitol Hill Via 15th Ave E")
                                    .font(.headline)
                            }

                            HStack(spacing: 8) {
                                Label("1_4339", systemImage: "bus.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Label("2 min ago", systemImage: "clock")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    Divider()

                    VStack(spacing: 12) {
                        Text("Stop Timeline")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("(Mock data - real view requires coordinator)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 40)
                }
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 8)
                .padding(.horizontal, 8)
            }
        }
    }
}
#endif
