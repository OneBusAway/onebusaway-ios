//
//  APIService.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/15/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

/// The core class for interacting with the OBA REST API.
///
/// This class is responsible for managing the base URL for the OBA REST API server,
/// the network queue for in-flight operations, and the query parameters that are
/// common to every request.
public class APIService: NSObject {
    let baseURL: URL
    let networkQueue: OperationQueue
    let defaultQueryItems: [URLQueryItem]

    public init(baseURL: URL, apiKey: String, uuid: String, appVersion: String, networkQueue: OperationQueue) {
        self.baseURL = baseURL

        var queryItems = [URLQueryItem]()
        queryItems.append(URLQueryItem(name: "key", value: apiKey))
        queryItems.append(URLQueryItem(name: "app_uid", value: uuid))
        queryItems.append(URLQueryItem(name: "app_ver", value: appVersion))
        queryItems.append(URLQueryItem(name: "version", value: "2"))
        self.defaultQueryItems = queryItems

        self.networkQueue = networkQueue
    }

    public convenience init(baseURL: URL, apiKey: String, uuid: String, appVersion: String) {
        self.init(baseURL: baseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, networkQueue: OperationQueue())
    }
}
