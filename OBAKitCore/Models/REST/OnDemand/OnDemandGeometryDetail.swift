//
//  OnDemandGeometryDetail.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The `geometryDetail` query parameter every `/api/ondemand` endpoint accepts
/// (wiki §3). `bbox` is always present at every level.
public enum OnDemandGeometryDetail: String, Sendable {
    /// `geometry` key omitted. Cheapest; enough for a list row.
    case none
    /// Import-time display geometry (≤256 points per ring, ~15 KB for an
    /// Alexandria-sized zone). What every screen in the app requests: the
    /// verbatim `full` geometry can reach ~750 KB for a county zone.
    case simplified
    /// The feed's verbatim geometry. Never used by the app's screens.
    case full
}
