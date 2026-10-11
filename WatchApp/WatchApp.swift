//
//  WatchApp.swift
//  WatchApp
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitWatch

/// The thin, white-label shell. Everything with a branch in it lives in
/// OBAKitWatch (views, host) or OBAKitCore (logic); an app opts in through its
/// `Apps/<App>/watch.yml`.
@main
struct WatchApp: App {
    @State private var host = WatchAppHost.fromMainBundle()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(host)
        }
    }
}
