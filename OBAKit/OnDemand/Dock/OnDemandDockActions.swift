//
//  OnDemandDockActions.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import OBAKitCore

/// Which list the overlap picker shows (spec 3.5). `nonisolated` because
/// `AppSheetRoute` (a `nonisolated` enum) carries it.
nonisolated enum OnDemandPickerScope: Equatable {
    /// The services containing the probe point (card footer, planner link).
    case insideOnly
    /// Every current match, inside and nearby (bar long-press).
    case nearby
}

nonisolated struct OnDemandPickerRequest {
    let matches: [OnDemandServiceMatch]
    let scope: OnDemandPickerScope
    let source: ProbeSource
    let coordinate: CLLocationCoordinate2D
}

/// What the dock surfaces can ask their host to do. Each shell supplies its
/// own implementation; the views never reach for a navigator themselves.
struct OnDemandDockActions {
    var openDetail: (OnDemandServiceMatch, OnDemandLocationCheck) -> Void
    var openPicker: (OnDemandPickerRequest) -> Void
    var call: (URL) -> Void
    var openURL: (URL) -> Void
    /// Zoom out to region level around these services (spec 3.4 thumbnail tap).
    var zoomOut: ([OnDemandServiceMatch]) -> Void
    /// Centre the map on a boundary point, keeping the zoom.
    var panTo: (CLLocationCoordinate2D) -> Void

    static let none = OnDemandDockActions(
        openDetail: { _, _ in },
        openPicker: { _ in },
        call: { _ in },
        openURL: { _ in },
        zoomOut: { _ in },
        panTo: { _ in }
    )
}
