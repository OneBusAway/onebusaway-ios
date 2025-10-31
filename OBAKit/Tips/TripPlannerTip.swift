//
//  TripPlannerTip.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import TipKit
import OBAKitCore

/// A tip that introduces users to the new trip planner feature.
struct TripPlannerTip: Tip {
    var title: Text {
        Text(Strings.tripPlannerTipTitle)
    }

    var message: Text? {
        Text(Strings.tripPlannerTipMessage)
    }

    var image: Image? {
        Image(systemName: "map.fill")
    }
}
