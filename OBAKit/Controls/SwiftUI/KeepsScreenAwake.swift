//
//  KeepsScreenAwake.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit

/// Holds the idle timer off while a live, self-refreshing screen is visible —
/// the SwiftUI equivalent of `Idleable`.
///
/// The `wasDisabledByUs` latch matters: another screen may already have
/// disabled the timer, and re-enabling it on our way out would cut that screen's
/// wake short.
private struct KeepsScreenAwakeModifier: ViewModifier {
    @State private var wasDisabledByUs = false

    func body(content: Content) -> some View {
        content
            .onAppear(perform: disable)
            .onDisappear(perform: reEnable)
    }

    private func disable() {
        guard !UIApplication.shared.isIdleTimerDisabled else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        wasDisabledByUs = true
    }

    private func reEnable() {
        guard wasDisabledByUs else { return }
        UIApplication.shared.isIdleTimerDisabled = false
        wasDisabledByUs = false
    }
}

extension View {
    func keepsScreenAwake() -> some View {
        modifier(KeepsScreenAwakeModifier())
    }
}
