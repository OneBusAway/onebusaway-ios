//
//  RegionsAPIService.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public class RegionsAPIService: APIService {
    lazy var URLBuilder = RESTAPIURLBuilder(baseURL: baseURL, defaultQueryItems: defaultQueryItems)

    public func getRegions(apiPath: String) -> DecodableOperation<RESTAPIResponse<[Region]>> {
        let url = URLBuilder.generateURL(path: apiPath)
        let operation = DecodableOperation(type: RESTAPIResponse<[Region]>.self, decoder: JSONDecoder.RESTDecoder(), URL: url, dataLoader: dataLoader)
        enqueueOperation(operation)
        return operation
    }
}
