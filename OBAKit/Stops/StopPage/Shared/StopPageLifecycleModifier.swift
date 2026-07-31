//
//  StopPageLifecycleModifier.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The seed key, shared between the modifier that reads it and the mode
/// toggle callbacks that write it.
enum StopPageLifecycleKeys {
    static let lastUsedStopSort = "OBALastUsedStopSort"
}

/// Lifecycle every Stop page presentation shares: start and stop the view
/// model, seed the last-used list mode, and show the Live Activity toast.
///
/// `.refreshable` is deliberately absent — the pushed screen and the
/// FloatingPanel sheet offer pull-to-refresh, the map sheet refreshes from its
/// toolbar button only, so that one modifier stays with each caller.
private struct StopPageLifecycleModifier: ViewModifier {
    @ObservedObject var viewModel: StopViewModel
    let userDefaults: UserDefaults
    let liveActivityStarted: Bool

    @State private var didSeedMode = false

    func body(content: Content) -> some View {
        content
            .task { await viewModel.start() }
            .onAppear(perform: seedLastUsedModeIfNeeded)
            .onDisappear { viewModel.deactivate() }
            .overlay(alignment: .bottom) {
                if liveActivityStarted {
                    Text(OBALoc("live_activity.started.title", value: "Tracking on Lock Screen", comment: "Toast shown when a Live Activity starts on the Lock Screen"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.tint, in: Capsule())
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: liveActivityStarted)
    }

    /// One-shot: a stop the user has never customised opens in the last mode
    /// they picked anywhere in the app. A stop with saved preferences owns its
    /// sort type and is left alone — including one deliberately set to
    /// Chronological, which `stopPreferences.sortType` alone can't tell apart
    /// from the default.
    private func seedLastUsedModeIfNeeded() {
        guard !didSeedMode else { return }
        didSeedMode = true
        guard !viewModel.hasCustomizedPreferences,
              let raw = userDefaults.string(forKey: StopPageLifecycleKeys.lastUsedStopSort),
              let seeded = StopSort(rawValue: raw)
        else { return }
        viewModel.seedSortType(seeded)
    }
}

extension View {
    func stopPageLifecycle(
        viewModel: StopViewModel,
        userDefaults: UserDefaults,
        liveActivityStarted: Bool
    ) -> some View {
        modifier(StopPageLifecycleModifier(
            viewModel: viewModel,
            userDefaults: userDefaults,
            liveActivityStarted: liveActivityStarted
        ))
    }
}
