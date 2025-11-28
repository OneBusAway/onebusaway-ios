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
import CoreLocation
import OBAKitCore

extension PresentationDetent {
    static let tip: PresentationDetent = .fraction(0.25)
}

/// A SwiftUI view that displays vehicle positions on a map
struct VehiclesMapView: View {
    @StateObject private var viewModel: MapViewModel
    @StateObject private var stopsViewModel: StopsViewModel
    @StateObject private var tripCoordinator: TripDisplayCoordinator
    @State private var showingFeedStatus = false
    @State private var selectedVehicle: RealtimeVehicle?
    @State private var selectedStop: Stop?
    @State private var stopSheetDetent: PresentationDetent = .medium
    @State private var routePolylineCoordinates: [CLLocationCoordinate2D]?
    @State private var tripDetails: TripDetails?

    init(application: Application) {
        _viewModel = StateObject(wrappedValue: MapViewModel(application: application))
        _stopsViewModel = StateObject(wrappedValue: StopsViewModel(application: application))
        _tripCoordinator = StateObject(wrappedValue: TripDisplayCoordinator(application: application))
    }

    var body: some View {
        ZStack {
            mapContent
            overlayContent
        }
        .sheet(isPresented: $tripCoordinator.isTripViewPresented) {
            VehicleTripView(
                coordinator: tripCoordinator,
                onNavigateToStop: { stop in
                    // Navigate to this stop (replace current stop sheet)
                    selectedStop = stop
                    stopSheetDetent = .medium
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .large))
        }
        .onFirstAppear {
            viewModel.centerOnUserLocation()
        }
    }

    // MARK: - Map Content

    private var mapContent: some View {
        Map(position: $viewModel.cameraPosition) {
            // Route polyline (rendered behind vehicle annotations)
            // Use tripCoordinator's polyline when trip view is presented, otherwise use local state
            if tripCoordinator.isTripViewPresented, let tripPolyline = tripCoordinator.routePolylineCoordinates {
                MapPolyline(coordinates: tripPolyline)
                    .stroke(tripCoordinator.routeColor.opacity(0.75), lineWidth: 5)
            } else if let routePolylineCoordinates {
                MapPolyline(coordinates: routePolylineCoordinates)
                    .stroke(routePolylineColor.opacity(0.75), lineWidth: 5)
            }

            // Vehicle location marker (for trip from stop sheet)
            if tripCoordinator.isTripViewPresented, let vehicleLocation = tripCoordinator.vehicleLocation {
                MapKit.Annotation("Vehicle", coordinate: vehicleLocation) {
                    VehicleLocationMarker(routeType: tripCoordinator.tripDetails?.trip?.route?.routeType ?? .bus)
                }
            }

            // Stop annotations
            ForEach(stopsViewModel.stops) { stop in
                MapKit.Annotation(stop.name, coordinate: stop.coordinate) {
                    StopAnnotationContent(stop: stop, iconFactory: viewModel.application.stopIconFactory)
                        .onTapGesture {
                            selectedStop = stop
                        }
                }
            }

            // Vehicle annotations
            ForEach(viewModel.vehicles) { vehicle in
                let label = vehicle.vehicleLabel ?? vehicle.vehicleID ?? "Bus"
                MapKit.Annotation(label, coordinate: vehicle.coordinate) {
                    buildAnnotation(vehicle: vehicle)
                }
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            stopsViewModel.regionDidChange(context.region)
        }
        .mapStyle(.standard(emphasis: .muted))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .sheet(
            item: $selectedVehicle,
            onDismiss: {
                routePolylineCoordinates = nil
                tripDetails = nil
            },
            content: { vehicle in
                VehicleDetailSheet(
                    vehicle: vehicle,
                    application: viewModel.application,
                    onNavigateToTrip: { tripConvertible in
                        navigateToTrip(tripConvertible)
                    }
                )
                .presentationDetents([.tip, .medium, .large])
                .presentationDragIndicator(.visible)
            }
        )
        .sheet(item: $selectedStop) { stop in
            StopViewControllerWrapper(
                application: viewModel.application,
                stop: stop,
                onArrivalDepartureTapped: { arrivalDeparture in
                    // Minimize the stop sheet and show trip view
                    stopSheetDetent = .tip
                    Task {
                        await tripCoordinator.selectArrivalDeparture(arrivalDeparture)
                    }
                }
            )
            .presentationDetents([.tip, .medium, .large], selection: $stopSheetDetent)
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .large))
        }
    }

    private var routePolylineColor: Color {
        if let uiColor = tripDetails?.trip.route?.color {
            return Color(uiColor)
        }
        return Color.accentColor
    }

    @ViewBuilder
    private func buildAnnotation(vehicle: RealtimeVehicle) -> some View {
        RealtimeVehicleAnnotationView(
            vehicle: vehicle,
            isSelected: selectedVehicle?.id == vehicle.id
        )
        .onTapGesture {
            // Clear previous polyline
            routePolylineCoordinates = nil
            tripDetails = nil
            selectedVehicle = vehicle
            withAnimation {
                centerOnVehicle(vehicle)
            }
            // Load new polyline
            Task {
                await loadRoutePolyline(for: vehicle)
            }
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

    /// Centers the map on the selected vehicle, positioning it in the upper third of the screen
    /// so it remains visible above the detail sheet.
    private func centerOnVehicle(_ vehicle: RealtimeVehicle) {
        // Offset the center point so the vehicle appears in the upper 1/3 of the screen.
        // The sheet covers roughly the bottom half, so we shift the map center down (south).
        let latitudeOffset = -0.003

        let offsetCoordinate = CLLocationCoordinate2D(
            latitude: vehicle.coordinate.latitude + latitudeOffset,
            longitude: vehicle.coordinate.longitude
        )

        viewModel.cameraPosition = .camera(
            MapCamera(centerCoordinate: offsetCoordinate, distance: 2000)
        )
    }

    /// Loads and displays the route polyline for the selected vehicle's trip.
    private func loadRoutePolyline(for vehicle: RealtimeVehicle) async {
        guard let apiService = viewModel.application.apiService else { return }

        // Build prefixed trip ID: {agencyID}_{tripID}
        guard let tripID = vehicle.tripID else { return }
        let prefixedTripID = "\(vehicle.agencyID)_\(tripID)"

        do {
            // 1. Get trip details to obtain shapeID
            let tripResponse = try await apiService.getTrip(
                tripID: prefixedTripID,
                vehicleID: nil,
                serviceDate: nil
            )
            guard let trip = tripResponse.entry.trip else { return }

            // 2. Fetch the shape using shapeID
            let shapeResponse = try await apiService.getShape(id: trip.shapeID)

            // 3. Decode the polyline
            guard let mkPolyline = shapeResponse.entry.polyline else { return }

            // 4. Extract coordinates from MKPolyline
            let pointCount = mkPolyline.pointCount
            var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
            mkPolyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))

            await MainActor.run {
                self.routePolylineCoordinates = coordinates
                self.tripDetails = tripResponse.entry
            }
        } catch {
            print("Failed to load route polyline: \(error)")
        }
    }

    // MARK: - Overlay Content

    private var overlayContent: some View {
        VStack {
            Spacer()

            HStack(alignment: .bottom) {
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
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 8)
        .frame(maxWidth: 44)
    }
}

/// A view representing a single vehicle annotation on the map
struct RealtimeVehicleAnnotationView: View {
    let vehicle: RealtimeVehicle
    var isSelected: Bool = false

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
        .scaleEffect(isSelected ? 1.4 : 1.0)
        .shadow(color: .black.opacity(isSelected ? 0.4 : 0.15), radius: isSelected ? 8 : 2)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

/// A marker showing the vehicle location on the map (for trip from stop sheet)
struct VehicleLocationMarker: View {
    let routeType: Route.RouteType

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 32, height: 32)

            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundColor(.white)
        }
        .shadow(color: .black.opacity(0.3), radius: 4)
    }

    private var iconName: String {
        switch routeType {
        case .lightRail: return "tram.fill"
        case .subway: return "tram.fill.tunnel"
        case .rail: return "train.side.front.car"
        case .ferry: return "ferry.fill"
        case .cableCar, .gondola: return "cablecar.fill"
        default: return "bus.fill"
        }
    }
}
