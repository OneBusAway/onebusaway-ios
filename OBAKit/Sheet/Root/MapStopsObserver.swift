//
//  MapStopsObserver.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Bridges `MapRegionManager`'s `stopsUpdated` delegate callback to a
/// `@Published` array so a SwiftUI `Map` can render stop annotations
/// reactively.
///
/// Intentionally separate from `MapViewModel`, which stays MapKit-free and does
/// not adopt the UIKit-era `MapRegionDelegate`.
@MainActor
final class MapStopsObserver: NSObject, ObservableObject, MapRegionDelegate {

    /// Stops currently loaded for the visible map region.
    @Published private(set) var stops: [Stop] = []

    init(mapRegionManager: MapRegionManager) {
        super.init()
        // Seed with whatever's already loaded so a re-created observer isn't empty.
        stops = mapRegionManager.stops
        mapRegionManager.addDelegate(self)
    }

    // MARK: - MapRegionDelegate

    func mapRegionManager(_ manager: MapRegionManager, stopsUpdated stops: [Stop]) {
        self.stops = stops
    }
}
