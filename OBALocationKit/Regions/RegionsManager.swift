//
//  RegionsManager.swift
//  OBALocationKit
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import OBANetworkingKit

public class RegionsManager: NSObject {
    private let apiService: RegionsAPIService
    private let locationService: LocationService

    public init(apiService: RegionsAPIService, locationService: LocationService) {
        self.apiService = apiService
        self.locationService = locationService
    }
}
