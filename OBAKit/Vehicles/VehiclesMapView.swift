//
//  VehiclesMapView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import MapKit
import OBAKitCore

/// A SwiftUI view that displays vehicle positions on a map
struct VehiclesMapView: View {
    @StateObject private var viewModel: VehiclesViewModel
    @State private var showingFeedStatus = false
    @State private var selectedVehicle: RealtimeVehicle?

    init(application: Application) {
        _viewModel = StateObject(wrappedValue: VehiclesViewModel(application: application))
    }

    var body: some View {
        ZStack {
            mapContent
            overlayContent
        }
        .task {
            viewModel.centerOnCurrentRegion()
            viewModel.startAutoRefresh()
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
        }
    }

    // MARK: - Map Content

    private var mapContent: some View {
        Map(position: $viewModel.cameraPosition) {
            ForEach(viewModel.vehicles) { vehicle in
                Annotation(
                    vehicle.vehicleLabel ?? vehicle.vehicleID ?? "Bus",
                    coordinate: vehicle.coordinate
                ) {
                    RealtimeVehicleAnnotationView(vehicle: vehicle)
                        .onTapGesture {
                            selectedVehicle = vehicle
                        }
                }
            }
        }
        .mapStyle(.standard)
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .sheet(item: $selectedVehicle) { vehicle in
            VehicleDetailSheet(vehicle: vehicle)
        }
    }

    // MARK: - Overlay Content

    private var overlayContent: some View {
        VStack {
            Spacer()

            HStack {
                statusView
                Spacer()
                infoButton
                refreshButton
            }
            .padding()
        }
    }

    private var infoButton: some View {
        Button {
            showingFeedStatus = true
        } label: {
            Image(systemName: "info.circle")
                .font(.title3)
                .padding(12)
                .background(.ultraThinMaterial, in: Circle())
        }
        .sheet(isPresented: $showingFeedStatus) {
            FeedStatusSheet(feedStatuses: viewModel.feedStatuses)
        }
    }

    private var statusView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if viewModel.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                    Text("Loading...")
                        .font(.caption)
                }
            } else if let error = viewModel.error {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            } else {
                Text("\(viewModel.vehicles.count) vehicles")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let lastUpdated = viewModel.lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var refreshButton: some View {
        Button {
            Task {
                await viewModel.refresh()
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.title3)
                .padding(12)
                .background(.ultraThinMaterial, in: Circle())
        }
        .disabled(viewModel.isLoading)
    }
}

/// A view representing a single vehicle annotation on the map
struct RealtimeVehicleAnnotationView: View {
    let vehicle: RealtimeVehicle

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue)
                .frame(width: 28, height: 28)

            Image(systemName: "bus.fill")
                .font(.system(size: 14))
                .foregroundColor(.white)
                .rotationEffect(.degrees(Double(vehicle.bearing ?? 0)))
        }
        .shadow(radius: 2)
    }
}
