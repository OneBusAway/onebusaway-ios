//
//  NearbyStopsView.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import CoreLocation
import OBAKitCore

struct NearbyStopsView: View {
    let model: NearbyStopsModel

    var body: some View {
        content
            .navigationTitle(model.regionName ?? OBALoc("nearby.title", value: "Nearby", comment: "Screen title before a transit region is known"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.refresh()
                    } label: {
                        Label(OBALoc("nearby.refresh", value: "Refresh", comment: "Toolbar button; re-requests location and reloads"), systemImage: "arrow.clockwise")
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .awaitingAuthorization:
            MessageView(
                text: OBALoc("nearby.awaiting_authorization", value: "Allow location access to see stops near you.", comment: "Shown while the system location prompt is up"),
                systemImage: "location"
            )
        case .locationDenied:
            MessageView(
                text: OBALoc("nearby.location_denied", value: "Location access is off. Nearby stops need your location.", comment: "Shown when location is denied or restricted"),
                systemImage: "location.slash"
            )
        case .locating:
            ProgressView(OBALoc("nearby.locating", value: "Finding your location…", comment: "Progress text"))
        case .noRegion:
            MessageView(
                text: OBALoc("nearby.no_region", value: "No transit region here.", comment: "The fix is outside every supported region"),
                systemImage: "map"
            )
        case .failed(let message):
            MessageView(
                text: message,
                systemImage: "exclamationmark.triangle",
                actionTitle: OBALoc("nearby.retry", value: "Retry", comment: "Button after a failure"),
                action: { model.refresh() }
            )
        case .empty:
            MessageView(
                text: OBALoc("nearby.empty", value: "No stops nearby.", comment: "The server returned zero stops"),
                systemImage: "bus"
            )
        case .loaded(let stops):
            List(stops) { stop in
                NavigationLink(value: stop) {
                    NearbyStopRow(stop: stop, origin: model.origin)
                }
            }
        }
    }
}

#Preview("Awaiting authorization") {
    NavigationStack { NearbyStopsView(model: NearbyStopsModel(phase: .awaitingAuthorization)) }
}

#Preview("Denied") {
    NavigationStack { NearbyStopsView(model: NearbyStopsModel(phase: .locationDenied)) }
}

#Preview("Locating") {
    NavigationStack { NearbyStopsView(model: NearbyStopsModel(phase: .locating)) }
}

#Preview("No region") {
    NavigationStack { NearbyStopsView(model: NearbyStopsModel(phase: .noRegion)) }
}

#Preview("Failed") {
    NavigationStack { NearbyStopsView(model: NearbyStopsModel(phase: .failed("The request timed out."))) }
}

#Preview("Empty") {
    NavigationStack { NearbyStopsView(model: NearbyStopsModel(phase: .empty, regionName: "Puget Sound")) }
}
