//
//  RegionsModelService.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBARegionsModelService)
public class RegionsModelService: ModelService {
    private let apiService: RegionsService

    public init(apiService: RegionsService, dataQueue: OperationQueue) {
        self.apiService = apiService
        super.init(dataQueue: dataQueue)
    }

    @objc public func getRegions() -> RegionsModelOperation {
        let service = apiService.getRegions()
        let data = RegionsModelOperation()

        transferData(from: service, to: data) { [unowned service, unowned data] in
            data.apiOperation = service
        }
        return data
    }
}
