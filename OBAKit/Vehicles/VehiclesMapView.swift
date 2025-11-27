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
import UIKit
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
        .sheet(isPresented: $showingFeedStatus) {
            FeedStatusSheet(viewModel: viewModel)
        }
        .task {
            viewModel.startAutoRefresh()
        }
        .onFirstAppear {
            viewModel.centerOnUserLocation()
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
        .mapStyle(.standard(emphasis: .muted))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .sheet(item: $selectedVehicle) { vehicle in
            VehicleDetailSheet(
                vehicle: vehicle,
                application: viewModel.application,
                onNavigateToTrip: { tripConvertible in
                    navigateToTrip(tripConvertible)
                }
            )
        }
    }

    // MARK: - Navigation

    private func navigateToTrip(_ tripConvertible: TripConvertible) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootVC = window.rootViewController else { return }

        let tripVC = TripViewController(
            application: viewModel.application,
            tripConvertible: tripConvertible
        )

        // Find the navigation controller and push
        if let tabBarController = rootVC as? UITabBarController,
           let navController = tabBarController.selectedViewController as? UINavigationController {
            navController.pushViewController(tripVC, animated: true)
        } else if let navController = rootVC.navigationController {
            navController.pushViewController(tripVC, animated: true)
        }
    }

    // MARK: - Overlay Content

    private var overlayContent: some View {
        VStack {
            Spacer()

            HStack(alignment: .bottom) {
                statusView
                Spacer()
                mapButtonBar
            }
            .padding()
        }
    }

    private var mapButtonBar: some View {
        VStack(spacing: 0) {
            Button {
                showingFeedStatus = true
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .frame(width: 44, height: 44)
            }

            Divider()

            Button {
                viewModel.centerOnUserLocation()
            } label: {
                Image(systemName: "location.fill")
                    .frame(width: 44, height: 44)
            }

            Divider()

            Button {
                Task {
                    await viewModel.refresh()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 44, height: 44)
            }
            .disabled(viewModel.isLoading)
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 8)
        .frame(maxWidth: 44)
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

                if viewModel.totalAgencyCount > 0 {
                    Text("Agencies: \(viewModel.enabledAgencyCount) of \(viewModel.totalAgencyCount)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A view representing a single vehicle annotation on the map
struct RealtimeVehicleAnnotationView: View {
    let vehicle: RealtimeVehicle

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 28, height: 28)

            Image(systemName: "bus.fill")
                .font(.system(size: 14))
                .foregroundColor(.white)
                .rotationEffect(.degrees(Double(vehicle.bearing ?? 0)))
        }
        .shadow(radius: 2)
    }
}
