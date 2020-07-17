//
//  MigrationRecentStop.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

@objc public class MigrationRecentStop: NSObject, NSCoding {
    public let title: String
    public let subtitle: String
    public let stopID: StopID
    public let coordinate: CLLocationCoordinate2D

    public required init?(coder: NSCoder) {
        guard
            let title = coder.decodeObject(forKey: "title") as? String,
            let subtitle = coder.decodeObject(forKey: "subtitle") as? String,
            let stopID = coder.decodeObject(forKey: "stopID") as? StopID,
            coder.containsValue(forKey: "latitude"),
            coder.containsValue(forKey: "longitude")
        else { return nil }

        self.title = title
        self.subtitle = subtitle
        self.stopID = stopID
        self.coordinate = CLLocationCoordinate2D(latitude: coder.decodeDouble(forKey: "latitude"), longitude: coder.decodeDouble(forKey: "longitude"))
    }

    public func encode(with coder: NSCoder) { fatalError("This class only supports initialization of an old object. You can't save it back!") }
}
