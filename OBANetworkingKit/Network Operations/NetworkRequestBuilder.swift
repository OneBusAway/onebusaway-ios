//
//  NetworkRequestBuilder.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

@objc(OBANetworkRequestBuilder)
public class NetworkRequestBuilder: NSObject {
    private let baseURL: URL
    private let networkQueue: NetworkQueue

    @objc public init(baseURL: URL, networkQueue: NetworkQueue) {
        self.baseURL = baseURL
        self.networkQueue = networkQueue
    }

    @objc public convenience init(baseURL: URL) {
        self.init(baseURL: baseURL, networkQueue: NetworkQueue())
    }

    // MARK: - Current Time
    @objc public func getCurrentTime(completion: ((_ operation: CurrentTimeOperation) -> Void)?) -> CurrentTimeOperation {
        let url = URL(string: "/api/where/current-time.json", relativeTo: baseURL)!
        let operation = CurrentTimeOperation(url: url)
        operation.completionBlock = { [weak operation] in
            if let operation = operation { completion?(operation) }
        }

        networkQueue.add(operation)

        return operation
    }
}
