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
import FloatingPanel

/// A SwiftUI view that displays vehicle positions on a map
struct VehiclesMapView: View {
    @StateObject private var viewModel: MapViewModel
    @StateObject private var stopsViewModel: StopsViewModel
    @StateObject private var tripCoordinator: TripDisplayCoordinator
    @State private var showingFeedStatus = false
    @State private var selectedStop: Stop?
    @State private var stopSheetDetent: PresentationDetent = .medium
    @State private var routePolylineCoordinates: [CLLocationCoordinate2D]?
    @State private var tripDetails: TripDetails?

    @State private var state: FloatingPanelState? = .hidden

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
        .onFirstAppear {
            viewModel.centerOnUserLocation()
        }
        .fixedFloatingPanel { _ in
            // Panel content goes here
        }
        .fixedFloatingPanelState($state)
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
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            stopsViewModel.regionDidChange(context.region)
        }
        .mapStyle(.standard(emphasis: .muted))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
    }

    private var routePolylineColor: Color {
        if let uiColor = tripDetails?.trip.route?.color {
            return Color(uiColor)
        }
        return Color.accentColor
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
