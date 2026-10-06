//
//  MapTypeButtonPresentation.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import UIKit

/// What the basemap button shows and says. Shared by the SwiftUI `MapTypeButton`
/// and `MapViewController`'s hover-bar button, which open the same Map sheet and
/// so have to describe it the same way.
enum MapTypeButtonPresentation {

    static func symbolName(for mapType: MapBaseType) -> String {
        switch mapType {
        case .standard: return "map"
        case .satellite: return "globe.americas.fill"
        case .hybrid: return "globe"
        }
    }

    /// The button opens `MapSheetView`, whose basemap picker is one of four
    /// sections — the others cover POI display, transit layers and rental
    /// modes — so "Map type" described a quarter of where it leads (#1412).
    static var accessibilityLabel: String {
        OBALoc(
            "map_controller.map_settings.accessibility_label",
            value: "Map settings",
            comment: "Voiceover text for the button that opens the Map settings sheet, which covers the base map, points of interest, transit layers and other travel modes."
        )
    }

    /// The basemap name, plus the layer count when the badge is showing one.
    ///
    /// The badge is decoration sitting on top of the button, hidden from
    /// VoiceOver, so without folding the count in here a VoiceOver user would
    /// have no way to learn the layer state short of opening the sheet — which
    /// is exactly the trip the badge exists to save.
    static func accessibilityValue(mapType: MapBaseType, layerCount: Int) -> String {
        let baseType = baseTypeName(mapType)
        guard layerCount > 0 else { return baseType }

        let format = OBALoc(
            "map_controller.map_type.accessibility_value_with_layers_fmt",
            value: "%1$@, %2$d layers on",
            comment: "Voiceover value combining the base map type with the number of enabled map layers. %1$@ is the base map type, %2$d is the layer count. Plural forms live in Localizable.stringsdict; the value above is only the not-found fallback."
        )
        // `localizedStringWithFormat`, not `String(format:)`: the latter expands
        // `%2$#@count@` but always resolves it against the root plural rule, so the
        // `few`/`many`/`zero`/`two` forms in the ar, pl, and ru entries could never
        // be selected. Invisible in English; wrong everywhere with more than two.
        return String.localizedStringWithFormat(format, baseType, layerCount)
    }

    /// The layer-count badge sits on the brand color. White on OneBusAway's green
    /// is under 3:1, so the digit takes whichever of white or black clears 4.5:1
    /// on the white-label app's brand.
    static var badgeTextColor: UIColor {
        ThemeColors.shared.brand.badgeTextColor(preferring: .white, minimumRatio: 4.5)
    }

    static func baseTypeName(_ mapType: MapBaseType) -> String {
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
