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

    /// Clears the accumulated stops. Call when the map zooms out past the
    /// stop-display threshold, mirroring the UIKit path, which removes all stop
    /// annotations when zoomed out (`reloadStopAnnotations`).
    func reset() {
        guard !stops.isEmpty else { return }
        stops = []
    }

    // MARK: - MapRegionDelegate

    // `MapRegionDelegate` is `@objc optional`; annotate the implementation so
    // Obj-C runtime discovery is explicit rather than relying on Swift's
    // inferred bridging.
    @objc
    func mapRegionManager(_ manager: MapRegionManager, stopsUpdated stops: [Stop]) {
        // Accumulate (union) rather than replace, matching the UIKit path:
        // `displayUniqueStopAnnotations` only *adds* stops not already on the map
        // and never removes one just because it left the latest region's result.
        // A settled camera re-issues the stops request on every pan, so replacing
        // the array would make the SwiftUI `Map` tear down and re-add annotations
        // each time — panning away and back would re-render the same pins (the
        // reported flicker). By only appending genuinely new stops (and keeping
        // existing instances), returning to a visited area is a no-op: nothing is
        // republished, so the pins already on screen stay put. The accumulated set
        // is bounded by `reset()` on zoom-out.
        let existingIDs = Set(self.stops.map(\.id))
        let newStops = stops.filter { !existingIDs.contains($0.id) }
        guard !newStops.isEmpty else { return }

        self.stops += newStops
    }
}
