//
//  MapTypeButton.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Floating map-type toggle rendered on the bottom-trailing cluster of
/// `MapPanelRootView`. Mirrors the UIKit `toggleMapTypeButton` in
/// `MapViewController` — same icons, same accessibility strings, same VM call.
struct MapTypeButton: View {
    let mapType: MapBaseType
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: .regular))
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .liquidGlassButtonStyle(borderShape: .circle, fallbackShape: Circle())
        .accessibilityLabel(Text(OBALoc(
            "map_controller.map_type.accessibility_label",
            value: "Map type",
            comment: "Voiceover text indicating that this button toggles the base map type."
        )))
        .accessibilityValue(Text(accessibilityValueText))
    }

    private var symbolName: String {
        mapType == .standard ? "map" : "globe"
    }

    private var accessibilityValueText: String {
        switch mapType {
        case .standard:
            return OBALoc(
                "map_controller.map_type.standard.accessibility_value",
                value: "standard",
                comment: "Voiceover text indicating the current map type as the standard base map."
            )
        case .hybrid:
            return OBALoc(
                "map_controller.map_type.hybrid.accessibility_value",
                value: "hybrid",
                comment: "Voiceover text indicating the current map type as the hybrid base map (satellite view with labels)."
            )
        }
    }
}
