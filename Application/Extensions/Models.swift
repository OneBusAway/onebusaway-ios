//
//  Models.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/22/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import MapKit

extension Stop: MKAnnotation {
    public var coordinate: CLLocationCoordinate2D {
        return location.coordinate
    }

    public var title: String? {
        return name
    }

    public var subtitle: String? {
        return direction
    }
}
