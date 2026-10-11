//
//  NearbyRoutesView.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import CoreLocation
import OBAKitCore

struct NearbyRoutesView: View {
    let model: NearbyRoutesModel

    var body: some View {
        content
            .navigationTitle(model.regionName ?? OBALoc("nearby.title", value: "Nearby", comment: "Screen title before a transit region is known"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.refresh()
                    } label: {
                        Label(Strings.refresh, systemImage: "arrow.clockwise")
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
        case .loading:
            ProgressView(OBALoc("nearby.loading", value: "Finding nearby routes…", comment: "Progress text while nearby stops' departures load"))
        case .noRegion:
            MessageView(
                text: OBALoc("nearby.no_region", value: "No transit region here.", comment: "The fix is outside every supported region"),
                systemImage: "map"
            )
        case .failed(let message):
            MessageView(
                text: message,
                systemImage: "exclamationmark.triangle",
                actionTitle: Strings.retry,
                action: { model.refresh() }
            )
        case .empty:
            MessageView(
                text: OBALoc("nearby.empty", value: "No departures nearby in the next hour.", comment: "No nearby stop has a departure in the next 60 minutes"),
                systemImage: "bus"
            )
        case .loaded(let directions):
            List(directions) { direction in
                NavigationLink(value: direction.key) {
                    RouteDirectionCard(direction: direction)
                }
            }
        }
    }
}

#Preview("Awaiting authorization") {
    NavigationStack { NearbyRoutesView(model: NearbyRoutesModel(phase: .awaitingAuthorization)) }
}

#Preview("Denied") {
    NavigationStack { NearbyRoutesView(model: NearbyRoutesModel(phase: .locationDenied)) }
}

#Preview("Locating") {
    NavigationStack { NearbyRoutesView(model: NearbyRoutesModel(phase: .locating)) }
}

#Preview("Loading") {
    NavigationStack { NearbyRoutesView(model: NearbyRoutesModel(phase: .loading, regionName: "Puget Sound")) }
}

#Preview("No region") {
    NavigationStack { NearbyRoutesView(model: NearbyRoutesModel(phase: .noRegion)) }
}

#Preview("Failed") {
    NavigationStack { NearbyRoutesView(model: NearbyRoutesModel(phase: .failed("The request timed out."))) }
}

#Preview("Empty") {
    NavigationStack { NearbyRoutesView(model: NearbyRoutesModel(phase: .empty, regionName: "Puget Sound")) }
}
