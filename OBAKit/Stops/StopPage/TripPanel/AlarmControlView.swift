//
//  AlarmControlView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// The trip panel's Live Activity block: a single "Track" button that starts
/// a Live Activity for this departure on the Lock Screen and Dynamic Island.
///
/// Text uses Dynamic Type text styles; the fixed circle dimension scales
/// with Dynamic Type via `@ScaledMetric`.
struct AlarmControlView: View {
    let alarmIsSet: Bool
    let leadTimeMinutes: Int
    let onSet: () -> Void
    let onCancel: () -> Void
    let onChange: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onSet) {
            Label(OBALoc("stop_page.live_activity.track", value: "Track on Lock Screen", comment: "Button in the trip panel to start a Live Activity for this departure on the Lock Screen and Dynamic Island"), systemImage: "waveform.circle.fill")
                .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(uiColor: ThemeColors.shared.brand))
        .foregroundStyle(.white)
        .font(.body.weight(.semibold))
    }
}
