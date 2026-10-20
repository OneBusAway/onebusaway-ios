//
//  RegionChangeSignal.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Tells `MapPanelRootView` the rider changed region: from More > Region, an
/// `add-region` link, or automatic selection following them somewhere new.
///
/// The UIKit map has `MapRegionManager` move its `MKMapView` for this, and that
/// map view is never on screen in the panel. `RegionsService` only calls
/// delegates for a real change, not for the same region again.
@MainActor
final class RegionChangeSignal: NSObject, ObservableObject, RegionsServiceDelegate {
    /// The region changed to, most recent last. Nil until one does.
    @Published private(set) var region: Region?

    init(regionsService: RegionsService) {
        super.init()
        // The delegate table is weak, so no explicit removal is needed.
        regionsService.addDelegate(self)
    }

    @objc
    func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        self.region = region
    }
}
