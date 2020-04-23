//
//  RegionsAPIService.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/11/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class RegionsAPIService: APIService {
    lazy var URLBuilder = RESTAPIURLBuilder(baseURL: baseURL, defaultQueryItems: defaultQueryItems)

    public func getRegions(apiPath: String) -> DecodableOperation<RESTAPIResponse<[Region]>> {
        let url = URLBuilder.generateURL(path: apiPath)
        let operation = DecodableOperation(type: RESTAPIResponse<[Region]>.self, decoder: JSONDecoder.RESTDecoder, URL: url)
        enqueueOperation(operation)
        return operation
    }
}
