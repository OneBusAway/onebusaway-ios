//
//  ServiceArea+MapKit.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore

extension ServiceArea {

    /// One `MKPolygon` per polygon of the area, holes attached as
    /// `interiorPolygons` so the fill renders the ring structure rather than
    /// painting over the holes. Empty when the area carries no geometry.
    var mkPolygons: [MKPolygon] {
        polygons.compactMap { rings in
            guard let exterior = rings.first, exterior.count >= 3 else { return nil }
            let holes = rings.dropFirst()
                .filter { $0.count >= 3 }
                .map { MKPolygon(coordinates: $0, count: $0.count) }
            return MKPolygon(coordinates: exterior, count: exterior.count, interiorPolygons: holes)
        }
    }
}
