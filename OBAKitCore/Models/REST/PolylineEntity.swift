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

public class PolylineEntity: NSObject, Decodable {
    public let points: String

    private enum CodingKeys: String, CodingKey {
        case points
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        points = try container.decode(String.self, forKey: .points)
    }

    public lazy var polyline: MKPolyline? = {
        let p = Polyline(encodedPolyline: points)
        return p.mkPolyline
    }()
}
