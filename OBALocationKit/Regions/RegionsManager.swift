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
    private let regionsService: RegionsService

    public init(regionsService: RegionsService) {
        self.regionsService = regionsService
    }
}
