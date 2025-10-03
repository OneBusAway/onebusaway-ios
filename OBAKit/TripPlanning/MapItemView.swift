//
//  MapItemView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import MapKit
import Contacts
import OBAKitCore

/// A SwiftUI view that displays detailed information about a map item (location/place).
///
/// This view presents location information in a modal-style interface
/// It includes sections for:
/// - A header with the location name and close button
/// - An "About" section displaying address, phone number, and website (if available)
/// - A "More" section with a link to view nearby transit stops
///
/// The view uses a `MapItemViewModel` to handle all business logic and user interactions.
public struct MapItemView: View {
    /// The view model that manages the data and business logic
    @StateObject private var viewModel: MapItemViewModel

    /// Environment value for dismissing the view
    @Environment(\.dismiss) private var dismiss

    /// State for controlling the Look Around viewer presentation
    @State private var showLookAroundViewer = false

    /// Initializes a new map item view.
    ///
    /// - Parameter viewModel: The view model containing the map item data and handling user actions
    public init(viewModel: MapItemViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ZStack {
            Color.clear
                .background(.ultraThinMaterial)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                headerView
                    .padding(.horizontal, ThemeMetrics.controllerMargin)
                    .padding(.top, ThemeMetrics.floatingPanelTopInset)

                List {
                    actionButtonsSection

                    if viewModel.lookAroundScene != nil {
                        lookAroundSection
                    }

                    if viewModel.hasAboutContent {
                        aboutSection
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
        .lookAroundViewer(
            isPresented: $showLookAroundViewer,
            initialScene: viewModel.lookAroundScene
        )
    }

    /// The header view containing the title and close button.
    private var headerView: some View {
        HStack(alignment: .top) {
            Text(viewModel.title)
                .font(.title)
                .fontWeight(.bold)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                viewModel.dismissView()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// The "About" section displaying location details such as address, phone, and URL.
    private var aboutSection: some View {
        Section(header: Text(OBALoc("map_item_controller.about_header", value: "About", comment: "about section header"))) {
            if let address = viewModel.formattedAddress {
                Button {
                    viewModel.openInMaps()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(address.components(separatedBy: "\n"), id: \.self) { line in
                                Text(line)
                                    .foregroundColor(.primary)
                            }
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            if let phone = viewModel.phoneNumber {
                Button {
                    viewModel.callPhoneNumber()
                } label: {
                    HStack {
                        Text(phone)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            if let url = viewModel.url {
                Button {
                    viewModel.openURL()
                } label: {
                    HStack {
                        Text(url.absoluteString)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The Look Around preview section
    private var lookAroundSection: some View {
        Section {
            if let scene = viewModel.lookAroundScene {
                LookAroundPreview(initialScene: scene)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture {
                        showLookAroundViewer = true
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "binoculars.fill")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                            .padding(8)
                    }
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    /// The action buttons section containing Plan a Trip and Nearby Stops buttons.
    private var actionButtonsSection: some View {
        Section {
            HStack(spacing: 8) {
                if viewModel.showPlanTripButton {
                    Button {
                        viewModel.planTrip()
                    } label: {
                        Text(OBALoc("map_item_controller.plan_trip", value: "Plan a trip", comment: "Button to plan a trip from this location"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button {
                    viewModel.showNearbyStops()
                } label: {
                    Text(OBALoc("map_item_controller.nearby_stops_row", value: "Nearby Stops", comment: "A table row that shows stops nearby."))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
}

// Preview is not available without Application.shared being available
// which requires a running app instance
