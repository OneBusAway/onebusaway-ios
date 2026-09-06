//
//  MapBaseType+MapStyle.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import SwiftUI

/// The basemap decision, in a form that can be compared and therefore tested.
///
/// `MapStyle` is opaque and not `Equatable`, so asserting on it directly is
/// impossible. Splitting the decision from its construction keeps the branch —
/// which previously collapsed satellite into hybrid — under test.
enum MapBaseStyleDescriptor: Equatable {
    case standard(pointsOfInterest: Bool)
    /// Imagery carries no labels, so it takes no points-of-interest argument.
    case imagery
    case hybrid(pointsOfInterest: Bool)
}

extension MapBaseType {
    func styleDescriptor(showingPointsOfInterest: Bool) -> MapBaseStyleDescriptor {
        switch self {
        case .standard: return .standard(pointsOfInterest: showingPointsOfInterest)
        case .satellite: return .imagery
        case .hybrid: return .hybrid(pointsOfInterest: showingPointsOfInterest)
        }
    }
}

extension MapBaseStyleDescriptor {
    var mapStyle: MapStyle {
        switch self {
        case .standard(let showsPOI):
            // `.muted` matches the UIKit map's `MKMapType.mutedStandard`.
            return .standard(emphasis: .muted, pointsOfInterest: showsPOI ? .all : .excludingAll)
        case .imagery:
            return .imagery
        case .hybrid(let showsPOI):
            return .hybrid(pointsOfInterest: showsPOI ? .all : .excludingAll)
        }
    }
}
