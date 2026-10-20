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
/// Traffic switches to the map panel's `Map`.
///
/// `MapRegionManager` applies those switches to its `MKMapView`, which the
/// panel never shows. Read through `@AppStorage`, so flipping one in Settings
/// redraws the map behind it.
struct MapPanelMapSettings: ViewModifier {
    let style: MapBaseStyleDescriptor

    @AppStorage private var showsScale: Bool
    @AppStorage private var showsTraffic: Bool

    init(style: MapBaseStyleDescriptor, userDefaults: UserDefaults) {
        self.style = style
        _showsScale = AppStorage(wrappedValue: true, MapRegionManager.mapViewShowsScaleKey, store: userDefaults)
        _showsTraffic = AppStorage(wrappedValue: true, MapRegionManager.mapViewShowsTrafficKey, store: userDefaults)
    }

    func body(content: Content) -> some View {
        content
            .mapStyle(style.mapStyle(showsTraffic: Self.effectiveShowsTraffic(showsTraffic)))
            .mapControls {
                MapCompass()
                // `.automatic` shows the scale while zooming, as `showsScale`
                // does on the UIKit map.
                MapScaleView()
                    .mapControlVisibility(showsScale ? .automatic : .hidden)
            }
    }

    /// Off in the Simulator, as `MapRegionManager.mapViewShowsTraffic` is: the
    /// traffic layer floods its console with shader errors there.
    static func effectiveShowsTraffic(_ setting: Bool) -> Bool {
        #if targetEnvironment(simulator)
        false
        #else
        setting
        #endif
    }
}
