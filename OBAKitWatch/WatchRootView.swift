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

/// The watch app's root: a TabView with Bookmarks and Nearby tabs.
/// Owns the models and the scene-phase driver so the shell stays a `@main`.
public struct WatchRootView: View {
    @Environment(WatchAppHost.self) private var host
    @Environment(\.scenePhase) private var scenePhase
    @State private var bookmarksModel: WatchBookmarksModel?
    @State private var nearby: NearbyRoutesModel?

    public init() {}

    public var body: some View {
        TabView {
            NavigationStack {
                Group {
                    if let bookmarksModel {
                        WatchBookmarksView(model: bookmarksModel)
                    } else {
                        ProgressView()
                    }
                }
                .navigationDestination(for: Stop.self) { stop in
                    StopArrivalsScreen(stop: stop)
                }
            }
            .tabItem {
                Label(OBALoc("bookmarks.tab", value: "Bookmarks", comment: "Bookmarks tab title"), systemImage: "bookmark.fill")
            }

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
            .tabItem {
                Label(OBALoc("nearby.tab", value: "Nearby", comment: "Nearby tab title"), systemImage: "location.fill")
            }
        }
        .task {
            host.refreshRegionsList()

            if bookmarksModel == nil {
                let bmModel = WatchBookmarksModel(host: host)
                bookmarksModel = bmModel
                bmModel.refresh()
            }

            if nearby == nil {
                let nbModel = NearbyRoutesModel(host: host)
                nearby = nbModel
                nbModel.refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                bookmarksModel?.refresh()
                nearby?.refresh()
            }
        }
        .onChange(of: host.authorizationStatus) { _, _ in
            nearby?.refresh()
        }
    }
}
