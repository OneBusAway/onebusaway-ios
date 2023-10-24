//
//  PolylineEntity.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit

public struct PolylineEntity: Codable, Hashable {
    public let points: String

    public var polyline: MKPolyline? {
        Polyline(encodedPolyline: points).mkPolyline
    }
}
