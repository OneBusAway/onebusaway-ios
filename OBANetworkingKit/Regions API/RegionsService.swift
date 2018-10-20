//
//  RegionsService.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/11/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBARegionsService)
public class RegionsService: APIService {

    @discardableResult @objc
    public func getRegions(completion: RESTAPICompletionBlock?) -> RegionsOperation {
        let url = RegionsOperation.buildURL(baseURL: baseURL, queryItems: defaultQueryItems)

        let operation = RegionsOperation(url: url)
        let completionOp = operationify(completionBlock: completion, dependentOn: operation)

        networkQueue.addOperations([operation, completionOp], waitUntilFinished: false)

        return operation
    }
}
