//
//  RefreshesOnForeground.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// Scene-phase policy for a self-refreshing screen: stop polling while the app
/// is backgrounded, start again when it comes back.
///
/// One modifier rather than an `.onChange(of: scenePhase)` per screen, because
/// the two rules in it are easy to get subtly wrong and impossible to notice
/// when they drift apart:
///
/// - Only the `.background → .active` edge restarts. `.inactive → .active` —
///   returning from Control Center, a banner or a system alert — never stopped
///   the timer, so restarting there is a redundant network call on every
///   notification the rider glances at.
/// - `.inactive` itself does nothing. The screen is still the rider's.
private struct RefreshesOnForegroundModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    let onForeground: () -> Void
    let onBackground: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { previous, phase in
            switch phase {
            case .active:
                if previous == .background { onForeground() }
            case .background:
                onBackground()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}

extension View {
    /// Deactivates a self-refreshing screen while the app is backgrounded and
    /// restarts it on the way back in.
    ///
    /// Pair with `keepsScreenAwake()` on any screen that also holds the idle
    /// timer off; that modifier carries the matching lease half of the same
    /// lifecycle.
    func refreshesOnForeground(
        onForeground: @escaping () -> Void,
        onBackground: @escaping () -> Void
    ) -> some View {
        modifier(RefreshesOnForegroundModifier(onForeground: onForeground, onBackground: onBackground))
    }
}
