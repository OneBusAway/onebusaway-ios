//
//  VehicleDetailSheet.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// A sheet that displays detailed information about a selected vehicle
struct VehicleDetailSheet: View {
    let vehicle: RealtimeVehicle
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                vehicleInfoSection
                agencyInfoSection
            }
            .navigationTitle("Vehicle Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Vehicle Info Section

    private var vehicleInfoSection: some View {
        Section("Vehicle Information") {
            if let label = vehicle.vehicleLabel, !label.isEmpty {
                DetailRow(label: "Vehicle", value: label)
            } else if let vehicleID = vehicle.vehicleID {
                DetailRow(label: "Vehicle ID", value: vehicleID)
            }

            if let routeID = vehicle.routeID {
                DetailRow(label: "Route", value: routeID)
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
