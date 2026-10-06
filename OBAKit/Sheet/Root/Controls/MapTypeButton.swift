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
                    .foregroundStyle(Color(uiColor: MapTypeButtonPresentation.badgeTextColor))
                    .frame(minWidth: 15, minHeight: 15)
                    .background(Color(uiColor: ThemeColors.shared.brand), in: Circle())
                    .offset(x: -2, y: 2)
                    .accessibilityHidden(true)
            }
        }
        // Shared with `MapViewController`'s hover-bar button, which opens the
        // same sheet; see `MapTypeButtonPresentation`.
        .accessibilityLabel(Text(MapTypeButtonPresentation.accessibilityLabel))
        .accessibilityValue(Text(MapTypeButtonPresentation.accessibilityValue(mapType: mapType, layerCount: badgeCount)))
    }

    private var symbolName: String {
        MapTypeButtonPresentation.symbolName(for: mapType)
    }
}
