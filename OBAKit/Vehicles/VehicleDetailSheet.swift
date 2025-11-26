//
//  VehicleDetailSheet.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// A sheet that displays detailed information about a selected vehicle
struct VehicleDetailSheet: View {
    let vehicle: RealtimeVehicle
    let application: Application
    var onNavigateToTrip: ((TripConvertible) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var tripDetails: TripDetails?
    @State private var isLoadingTrip = false
    @State private var tripLoadError: Error?

    /// Constructs the prefixed trip ID in OBA format: `{agencyID}_{tripID}`
    private var prefixedTripID: String? {
        guard let tripID = vehicle.tripID else { return nil }
        return "\(vehicle.agencyID)_\(tripID)"
    }

    var body: some View {
        NavigationStack {
            List {
                vehicleInfoSection
                agencyInfoSection
            }
            .navigationTitle(tripDetails?.trip.routeHeadsign ?? "Vehicle Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await loadTripDetails()
        }
    }

    // MARK: - Trip Loading

    private func loadTripDetails() async {
        guard let prefixedTripID = prefixedTripID,
              let apiService = application.apiService else { return }

        isLoadingTrip = true
        do {
            let response = try await apiService.getTrip(
                tripID: prefixedTripID,
                vehicleID: nil,
                serviceDate: nil
            )
            tripDetails = response.entry
        } catch {
            tripLoadError = error
        }
        isLoadingTrip = false
    }

    /// Route row that becomes tappable when trip details are loaded
    @ViewBuilder
    private var routeRow: some View {
        if let tripDetails = tripDetails {
            Button {
                let tripConvertible = TripConvertible(tripDetails: tripDetails)
                dismiss()
                onNavigateToTrip?(tripConvertible)
            } label: {
                HStack {
                    Text("Route")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(tripDetails.trip.routeHeadsign)
                        .foregroundStyle(.blue)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if isLoadingTrip {
            HStack {
                Text("Route")
                    .foregroundStyle(.secondary)
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
            }
        } else if let routeID = vehicle.routeID {
            DetailRow(label: "Route", value: routeID)
        }
    }

    // MARK: - Vehicle Info Section

    private var vehicleInfoSection: some View {
        Section("Vehicle Information") {
            if let label = vehicle.vehicleLabel, !label.isEmpty {
                DetailRow(label: "Vehicle", value: label)
            } else if let vehicleID = vehicle.vehicleID {
                DetailRow(label: "Vehicle ID", value: vehicleID)
            }

            if vehicle.routeID != nil {
                routeRow
            }

            if let tripID = vehicle.tripID {
                DetailRow(label: "Trip", value: tripID)
            }

            if let bearingDesc = vehicle.bearingDescription {
                DetailRow(label: "Heading", value: bearingDesc)
            }

            if let timestamp = vehicle.timestamp {
                HStack {
                    Text("Updated")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(timestamp, style: .relative)
                    Text("ago")
                }
            }

            DetailRow(
                label: "Location",
                value: String(format: "%.5f, %.5f", vehicle.coordinate.latitude, vehicle.coordinate.longitude)
            )
        }
    }

    // MARK: - Agency Info Section

    private var agencyInfoSection: some View {
        Section("Agency Information") {
            DetailRow(label: "Agency", value: vehicle.agencyName)

            if let phone = vehicle.agencyPhone {
                Button {
                    if let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                        openURL(url)
                    }
                } label: {
                    HStack {
                        Text("Phone")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(phone)
                            .foregroundStyle(.blue)
                    }
                }
            }

            if let email = vehicle.agencyEmail {
                Button {
                    if let url = URL(string: "mailto:\(email)") {
                        openURL(url)
                    }
                } label: {
                    HStack {
                        Text("Email")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(email)
                            .foregroundStyle(.blue)
                    }
                }
            }

            if let agencyURL = vehicle.agencyURL {
                Button {
                    openURL(agencyURL)
                } label: {
                    HStack {
                        Text("Website")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(agencyURL.host ?? agencyURL.absoluteString)
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                    }
                }
            }

            if let fareURL = vehicle.fareURL {
                Button {
                    openURL(fareURL)
                } label: {
                    HStack {
                        Text("Fare Info")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(fareURL.host ?? fareURL.absoluteString)
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

/// A simple row displaying a label and value
private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }
}
