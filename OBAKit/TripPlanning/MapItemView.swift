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
                    .padding(.bottom, ThemeMetrics.padding)

                List {
                    if viewModel.hasAboutContent {
                        aboutSection
                    }

                    moreSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
    }

    /// The header view containing the title and close button.
    private var headerView: some View {
        HStack(alignment: .top) {
            Text(viewModel.title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                dismiss()
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

    /// The "More" section containing additional actions such as viewing nearby stops.
    private var moreSection: some View {
        Section(header: Text(OBALoc("map_item_controller.more_header", value: "More", comment: "More options header"))) {
            Button {
                viewModel.showNearbyStops()
            } label: {
                HStack {
                    Text(OBALoc("map_item_controller.nearby_stops_row", value: "Nearby Stops", comment: "A table row that shows stops nearby."))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(.tertiaryLabel))
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// Preview is not available without Application.shared being available
// which requires a running app instance
