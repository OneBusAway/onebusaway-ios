//
//  StopArrivalsScreen.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Owns the stop screen's model for the lifetime of the pushed view, so a
/// parent re-render (scene phase, authorization change) cannot replace it
/// with a fresh `.loading` model and orphan the running poll.
struct StopArrivalsScreen: View {
    let stop: Stop
    @Environment(WatchAppHost.self) private var host
    @State private var model: StopArrivalsModel?

    var body: some View {
        Group {
            if let model {
                StopArrivalsView(model: model)
            } else {
                ProgressView()
            }
        }
        .task {
            guard model == nil else { return }
            model = StopArrivalsModel(host: host, stop: stop)
        }
    }
}
