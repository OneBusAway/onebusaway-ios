//
//  RegionsAPIService.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/11/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class RegionsAPIService: APIService {

    public func getRegions() -> RegionsOperation {
        let url = RegionsOperation.buildURL(baseURL: baseURL, queryItems: defaultQueryItems)
        let request = RegionsOperation.buildRequest(for: url)
        let operation = RegionsOperation(request: request)
        networkQueue.addOperation(operation)

        return operation
    }
}
