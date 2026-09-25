//
//  WatchRootView.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The watch app's root: one navigation stack, Nearby routes at the bottom of
/// it, then a route direction, then (optionally) a stop's full arrivals.
/// Owns the models and the scene-phase driver so the shell stays a `@main`.
public struct WatchRootView: View {
    @Environment(WatchAppHost.self) private var host
    @Environment(\.scenePhase) private var scenePhase
    @State private var nearby: NearbyRoutesModel?

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if let nearby {
                    NearbyRoutesView(model: nearby)
                } else {
                    ProgressView()
                }
            }
            .navigationDestination(for: RouteDirectionKey.self) { key in
                if let nearby {
                    RouteDirectionScreen(key: key, nearby: nearby)
                }
            }
            .navigationDestination(for: Stop.self) { stop in
                StopArrivalsScreen(stop: stop)
            }
        }
        .task {
            guard nearby == nil else { return }
            let model = NearbyRoutesModel(host: host)
            nearby = model
            host.refreshRegionsList()
            model.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            // A fresh fix on every foreground; the initial launch is covered by
            // `.task`, and `onChange` does not fire for the initial value.
            if phase == .active {
                nearby?.refresh()
            }
        }
        .onChange(of: host.authorizationStatus) { _, _ in
            // The grant after the system prompt; a denial lands in `.locationDenied`.
            nearby?.refresh()
        }
    }
}
