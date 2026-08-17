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

/// Floating basemap button on the bottom-trailing cluster of
/// `MapPanelRootView`. Opens the Map sheet, which absorbs the old
/// standard/hybrid toggle as its basemap tiles — the same move
/// `MapViewController`'s basemap button already made.
///
/// The badge carries the active-layer count: layer state stays readable
/// without opening anything.
struct MapTypeButton: View {
    let mapType: MapBaseType
    let badgeCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: .regular))
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .liquidGlassButtonStyle(borderShape: .circle, fallbackShape: Circle())
        .overlay(alignment: .topTrailing) {
            if badgeCount > 0 {
                Text(String(badgeCount))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 15, minHeight: 15)
                    .background(Color(uiColor: ThemeColors.shared.brand), in: Circle())
                    .offset(x: -2, y: 2)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(Text(OBALoc(
            "map_controller.map_type.accessibility_label",
            value: "Map type",
            comment: "Voiceover text for the button that opens the Map settings sheet."
        )))
        .accessibilityValue(Text(accessibilityValueText))
    }

    private var symbolName: String {
        switch mapType {
        case .standard: return "map"
        case .satellite: return "globe.americas.fill"
        case .hybrid: return "globe"
        }
    }

    /// The basemap name, plus the layer count when the badge is showing one.
    ///
    /// The badge itself is `accessibilityHidden` — it is decoration sitting on
    /// top of the button — so without folding the count in here a VoiceOver user
    /// would have no way to learn the layer state short of opening the sheet,
    /// which is exactly the trip the badge exists to save.
    private var accessibilityValueText: String {
        guard badgeCount > 0 else { return baseTypeValueText }

        return String(
            format: OBALoc(
                "map_controller.map_type.accessibility_value_with_layers_fmt",
                value: "%1$@, %2$d layers on",
                comment: "Voiceover value combining the base map type with the number of enabled map layers. %1$@ is the base map type, %2$d is the layer count."
            ),
            baseTypeValueText,
            badgeCount
        )
    }

    private var baseTypeValueText: String {
        switch mapType {
        case .standard:
            return OBALoc(
                "map_controller.map_type.standard.accessibility_value",
                value: "standard",
                comment: "Voiceover text indicating the current map type as the standard base map."
            )
        case .satellite:
            return OBALoc(
                "map_controller.map_type.satellite.accessibility_value",
                value: "satellite",
                comment: "Voiceover text indicating the current map type as the satellite base map."
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
