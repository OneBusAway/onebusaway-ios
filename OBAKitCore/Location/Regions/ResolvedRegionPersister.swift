//
//  ResolvedRegionPersister.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Keeps `ResolvedRegionStore` in step with `RegionsService.currentRegion`.
///
/// Owned by the *app* only. An extension must never create one: its
/// `RegionsService` cannot see custom regions, so it would overwrite the app's
/// correct value with nil.
///
/// Writes on four triggers — launch (init), `updatedRegion`,
/// `updatedRegionsList`, and `updatedCustomRegions`. All four are needed: the
/// `currentRegion` setter returns early on an unchanged identifier, so a
/// server-side edit to the current region arrives only as a list update, and an
/// edit to the current custom region only as a custom-regions update.
@MainActor
public final class ResolvedRegionPersister: NSObject, RegionsServiceDelegate {
    private weak var regionsService: RegionsService?
    private let store: ResolvedRegionStore
    private let userDefaults: UserDefaults

    public init(regionsService: RegionsService, store: ResolvedRegionStore, userDefaults: UserDefaults? = nil) {
        self.regionsService = regionsService
        self.store = store
        self.userDefaults = userDefaults ?? store.userDefaults
        super.init()

        // `RegionsService` holds its delegates weakly; the owner retains us.
        regionsService.addDelegate(self)
        persist()
    }

    /// Writes the current region, or clears the store when there is no current selection.
    ///
    /// If `currentRegion` evaluates to `nil`, we preserve the store's cached region only while
    /// the regions list cannot yet be trusted (e.g. offline launch or failed refresh) and a selection
    /// identifier is stored. Once the regions list is trusted or if no identifier is stored, we clear the store.
    public func persist() {
        if let currentRegion = regionsService?.currentRegion {
            store.write(currentRegion)
        } else if regionsService?.canTrustRegionsList == true || userDefaults.object(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey) == nil {
            store.write(nil)
        }
    }

    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        persist()
    }

    public func regionsService(_ service: RegionsService, updatedRegionsList regions: [Region]) {
        persist()
    }

    public func regionsService(_ service: RegionsService, updatedCustomRegions regions: [Region]) {
        persist()
    }
}
