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
/// This view presents location information in a modal-style interface, styled similarly to Apple Maps.
///  It includes sections for:
///  A header with Name, Item Category, Short Address
///  An apple maps styled buttons row for Plan A Trip, Call, Website (if available),
///  also including a Nearby Stops button which adjusts dynamically according to the availability of previous buttons
/// The view uses a `MapItemViewModel` to handle all business logic and user interactions.
public struct MapItemView: View {
    /// The view model that manages the data and business logic
    private var viewModel: MapItemViewModel

    /// Environment value for dismissing the view
    @Environment(\.dismiss) private var dismiss

    /// State for controlling the Look Around viewer presentation
    @State private var showLookAroundViewer = false

    /// Initializes a new map item view.
    ///
    /// - Parameter viewModel: The view model containing the map item data and handling user actions
    public init(viewModel: MapItemViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            Color.clear
                .background(.ultraThinMaterial)
                .ignoresSafeArea(.all)

            VStack(spacing: 0) {
                headerView
                    .padding(.top, 20)
                    .padding(.horizontal)

                ScrollView {
                     VStack(spacing: 20) {
                        // Action Buttons and Nearby Stops
                        VStack(spacing: 12) {
                            actionButtonsRow
                                .padding(.horizontal)

                            // Nearby Stops Button - show as full-width only when call/website buttons exist
                            if viewModel.phoneNumber != nil || viewModel.url != nil {
                                Button(
                                    action: {
                                        viewModel.showNearbyStops()
                                    },
                                    label: {
                                        HStack {
                                            Text(OBALoc("map_item_controller.nearby_stops_row", value: "View Nearby Transit Stops", comment: "Button to view nearby stops"))
                                                .bold()
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .bold()
                                        }
                                        .padding()
                                        .background(Color(uiColor: .secondarySystemBackground))
                                        .clipShape(.rect(cornerRadius: 12))
                                    }
                                )
                                .padding(.horizontal)
                                .foregroundStyle(.primary)
                            }
                        }

                        if let scene = viewModel.lookAroundScene {
                            lookAroundSection(scene: scene)
                        }

                        if viewModel.hasAboutContent {
                            aboutSection
                                .padding(.horizontal)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.top)
                }
            }
        }
        .lookAroundViewer(
            isPresented: $showLookAroundViewer,
            initialScene: viewModel.lookAroundScene
        )
    }

    /// The header view containing the title and close button.
    private var headerView: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 2) {
                Text(viewModel.title)
                    .font(.headline)
                    .bold()
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 44)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .padding(.horizontal, 44)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)

            HStack(alignment: .top) {
                // Share Button
                Button("Share", systemImage: "square.and.arrow.up") {
                    viewModel.shareLocation()
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
                .background(.regularMaterial)
                .clipShape(.circle)

                Spacer()

                // Close Button
                Button("Close", systemImage: "xmark") {
                    viewModel.dismissView()
                }
                .labelStyle(.iconOnly)
                .font(.body)
                .bold()
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(.regularMaterial)
                .clipShape(.circle)
            }
        }
    }

    private var subtitle: String? {
        var categoryPart: String?
        var locationParts: [String] = []

        if let category = viewModel.pointOfInterestCategory {
            let formattedCategory = category.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression, range: nil).trimmingCharacters(in: .whitespaces)
            categoryPart = formattedCategory
        }

        if let locality = viewModel.mapItem.placemark.locality {
            locationParts.append(locality)
        }
        if let adminArea = viewModel.mapItem.placemark.administrativeArea {
            locationParts.append(adminArea)
        }

        var result: String?

        if let category = categoryPart {
            let locationString = locationParts.joined(separator: ", ")
            if !locationString.isEmpty {
                result = "\(category) · \(locationString)"
            } else {
                result = category
            }
        } else if !locationParts.isEmpty {
            result = locationParts.joined(separator: ", ")
        }

        return result
    }

    /// The action buttons row containing Plan Trip, Call, Website, and Nearby Stops buttons.
    private var actionButtonsRow: some View {
        HStack(spacing: 12) {
            // Plan Trip (Primary)
            if viewModel.showPlanTripButton {
                actionButton(
                    title: OBALoc("map_item_controller.plan_trip", value: "Plan Trip", comment: "Plan trip button"),
                    icon: "arrow.triangle.turn.up.right.circle.fill",
                    backgroundColor: Color(uiColor: ThemeColors.shared.brand),
                    foregroundColor: .white
                ) {
                    viewModel.planTrip()
                }
            }

            // Nearby Stops - show next to Plan Trip when call/website buttons are absent
            if viewModel.phoneNumber == nil && viewModel.url == nil {
                actionButton(
                    title: OBALoc("map_item_controller.nearby_stops", value: "Nearby Stops", comment: "Nearby stops button"),
                    icon: "mappin.and.ellipse",
                    backgroundColor: Color(uiColor: .secondarySystemBackground),
                    foregroundColor: Color(uiColor: ThemeColors.shared.brand)
                ) {
                    viewModel.showNearbyStops()
                }
            }

            if viewModel.phoneNumber != nil {
                actionButton(
                    title: OBALoc("map_item_controller.call", value: "Call", comment: "Call button"),
                    icon: "phone.fill",
                    backgroundColor: Color(uiColor: .secondarySystemBackground),
                    foregroundColor: Color(uiColor: ThemeColors.shared.brand)
                ) {
                    viewModel.callPhoneNumber()
                }
            }

            if viewModel.url != nil {
                actionButton(
                    title: OBALoc("map_item_controller.website", value: "Website", comment: "Website button"),
                    icon: "safari.fill",
                    backgroundColor: Color(uiColor: .secondarySystemBackground),
                    foregroundColor: Color(uiColor: ThemeColors.shared.brand)
                ) {
                    viewModel.openURL()
                }
            }
        }
    }

    private func actionButton(title: String, icon: String, backgroundColor: Color, foregroundColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    /// The lookAroundView section.
    private func lookAroundSection(scene: MKLookAroundScene) -> some View {
        LookAroundPreview(initialScene: scene)
            .frame(height: 180)
            .clipShape(.rect(cornerRadius: 12))
            .padding(.horizontal)
            .onTapGesture {
                showLookAroundViewer = true
            }
    }

    /// The "About" section displaying location details such as address, phone, and URL.
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(OBALoc("map_item_controller.about_header", value: "About", comment: "About section header"))
                .font(.headline)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                if let address = viewModel.formattedAddress {
                    aboutRow(content: address) {
                        viewModel.openInMaps()
                    }

                    if viewModel.phoneNumber != nil || viewModel.url != nil { Divider() }
                }

                if let phone = viewModel.phoneNumber {
                    aboutRow(content: phone) {
                        viewModel.callPhoneNumber()
                    }

                    if viewModel.url != nil { Divider() }
                }

                if let url = viewModel.url {
                    aboutRow(content: url.host ?? url.absoluteString) {
                        viewModel.openURL()
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    private func aboutRow(content: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(content)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding()
        }
        .foregroundStyle(.primary)
    }
}

// Preview is not available without Application.shared being available
// which requires a running app instance
