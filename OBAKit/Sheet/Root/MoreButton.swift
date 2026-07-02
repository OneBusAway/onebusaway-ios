//
//  MoreButton.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Floating capsule button rendered in the top-trailing overlay slot of
/// `MapPanelRootView`. Tapping it pushes `AppSheetRoute.more` onto the
/// sheet coordinator; the button itself is pure presentation.
struct MoreButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "line.3.horizontal")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .regularGlassEffectIfAvailable(in: Capsule())
        .accessibilityLabel(Text(OBALoc(
            "more_controller.title",
            value: "More",
            comment: "Title of the More tab / accessibility label for the map-panel more button."
        )))
    }
}
