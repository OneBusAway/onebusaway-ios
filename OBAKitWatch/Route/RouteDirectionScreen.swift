//
//  RouteDirectionScreen.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Owns the route screen's model for the lifetime of the pushed view, like
/// `StopArrivalsScreen`. The model is seeded once from the Nearby list as it
/// stood at the tap; a later Nearby refresh does not replace it.
struct RouteDirectionScreen: View {
    let key: RouteDirectionKey
    let nearby: NearbyRoutesModel
    @Environment(WatchAppHost.self) private var host
    @State private var model: RouteDirectionModel?
    @State private var missing = false

    var body: some View {
        Group {
            if let model {
                RouteDirectionView(model: model)
            } else if missing {
                // The list refreshed between the tap and the push and this
                // direction is no longer in it.
                MessageView(
                    text: OBALoc("arrivals.empty", value: "No departures in the next 60 minutes.", comment: "Empty state"),
                    systemImage: "bus"
                )
            } else {
                ProgressView()
            }
        }
        .task {
            guard model == nil, !missing else { return }
            let directions = nearby.directions
            guard
                let direction = directions.first(where: { $0.key == key }),
                let origin = nearby.origin
            else {
                missing = true
                return
            }
            model = RouteDirectionModel(
                host: host,
                origin: origin,
                direction: direction,
                opposite: NearbyRouteDirections.opposite(of: key, in: directions),
                snapshotDate: nearby.loadedAt ?? Date()
            )
        }
    }
}
