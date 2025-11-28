//
//  HomeView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The main panel view for the home screen, combining nearby stops, recent stops, and bookmarks.
/// Modeled on the Apple Maps panel experience.
struct HomeView: View {
    let application: Application
    let nearbyStops: [Stop]
    let onStopSelected: (Stop) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Nearby Stops section
                StopListView(
                    title: "Nearby Stops",
                    stops: nearbyStops,
                    iconFactory: application.stopIconFactory,
                    onStopSelected: onStopSelected
                )

                // Recent Stops section
                RecentStopsView(application: application, onStopSelected: onStopSelected)

                // Bookmarks section
                BookmarksView(application: application, onStopSelected: onStopSelected)
            }
        }
    }
}
