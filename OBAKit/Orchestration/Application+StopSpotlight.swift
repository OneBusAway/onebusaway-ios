//
//  Application+StopSpotlight.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore

// MARK: - Stops in Spotlight

extension Application {
    /// Starts keeping the current region's stops in Spotlight, and indexes them
    /// now: `regionsService(_:updatedRegion:)` doesn't fire on a normal launch.
    /// Called from `application(_:didFinishLaunching:)`, so only a launched app
    /// writes the index.
    func startStopSpotlightIndexing() {
        stopSpotlightIndexer = StopSpotlightIndexer(
            userDataStore: userDataStore,
            stopCache: stopCacheRepository,
            currentRegion: { [weak self] in self?.currentRegion }
        )
        stopSpotlightIndexer?.replaceAll()
    }
}
