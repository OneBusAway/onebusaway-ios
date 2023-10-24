//
//  PolylineEntity.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MetaCodable
import MapKit

@Codable
public struct PolylineEntity: Hashable {
    public let points: String

    @IgnoreCoding
    public lazy var polyline: MKPolyline? = {
        let p = Polyline(encodedPolyline: points)
        return p.mkPolyline
    }()
}
