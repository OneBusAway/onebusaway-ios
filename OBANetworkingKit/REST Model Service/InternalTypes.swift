//
//  InternalTypes.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/20/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation

internal struct LocationModel: Codable {
    let latitude: Double
    let longitude: Double

    enum CodingKeys: String, CodingKey {
        case latitude = "lat"
        case longitude = "lon"
    }
}

internal extension CLLocation {
    convenience init(locationModel: LocationModel) {
        self.init(latitude: locationModel.latitude, longitude: locationModel.longitude)
    }

    convenience init<K>(container: KeyedDecodingContainer<K>, key: K) throws where K: CodingKey {
        let locationModel = try container.decode(LocationModel.self, forKey: key)
        self.init(latitude: locationModel.latitude, longitude: locationModel.longitude)
    }
}
