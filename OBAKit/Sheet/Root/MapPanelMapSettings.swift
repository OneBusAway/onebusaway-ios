//
//  MapPanelMapSettings.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import SwiftUI
import OBAKitCore

/// Applies the map's style and the Settings screen's Show Scale and Show
/// Traffic switches to the map panel's `Map`. Show Heading changes the map's
/// content rather than the map, so ``MapPanelUserLocation`` applies it.
///
/// `MapRegionManager` applies those switches to its `MKMapView`, which the
/// panel never shows. Read through `@AppStorage`, so flipping one in Settings
/// redraws the map behind it.
struct MapPanelMapSettings: ViewModifier {
    let style: MapBaseStyleDescriptor

    @AppStorage private(set) var showsScale: Bool
    @AppStorage private(set) var showsTraffic: Bool

    init(style: MapBaseStyleDescriptor, userDefaults: UserDefaults) {
        self.style = style
        _showsScale = AppStorage(wrappedValue: MapDisplaySettings.defaultShowsScale, MapDisplaySettings.showsScaleKey, store: userDefaults)
        _showsTraffic = AppStorage(wrappedValue: MapDisplaySettings.defaultShowsTraffic, MapDisplaySettings.showsTrafficKey, store: userDefaults)
    }

    func body(content: Content) -> some View {
        content
            .mapStyle(style.mapStyle(showsTraffic: MapDisplaySettings.effectiveShowsTraffic(showsTraffic)))
            .mapControls {
                MapCompass()
                // `.automatic` shows the scale while zooming, as `showsScale`
                // does on the UIKit map.
                MapScaleView()
                    .mapControlVisibility(showsScale ? .automatic : .hidden)
            }
    }
}
