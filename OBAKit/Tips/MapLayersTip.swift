//
//  MapLayersTip.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import TipKit
import OBAKitCore

/// A tip pointing at the map toolbar's basemap button the first time a region
/// offers bike and scooter rental layers. That button opens the Map sheet,
/// where the rental layers and their range filter are turned on and off.
///
/// Shown once, then never again — `MaxDisplayCount(1)` — because it announces a
/// feature rather than teaching a repeated gesture.
///
/// `IgnoresDisplayFrequency` is what makes "first launch" actually mean first
/// launch. `Tips.configure` sets an app-wide `.displayFrequency(.hourly)` budget
/// that only one tip may spend per hour, and `TripPlannerTip` competes for it on
/// this very screen. Measured on a fresh install: without this option the tip
/// reports `shouldDisplay == false` for the whole first session, which is the
/// only session it exists for. Exempting it does not spend the budget, so the
/// trip-planner tip still gets its own turn on a later launch.
struct MapLayersTip: Tip {
    var title: Text {
        Text(Strings.mapLayersTipTitle)
    }

    var message: Text? {
        Text(Strings.mapLayersTipMessage)
    }

    var image: Image? {
        Image(systemName: "bicycle")
    }

    var options: [any TipOption] {
        [Tips.MaxDisplayCount(1), Tips.IgnoresDisplayFrequency(true)]
    }
}
