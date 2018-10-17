//
//  APIService.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/15/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class APIService: NSObject {
    let baseURL: URL
    let networkQueue: NetworkQueue
    let defaultQueryItems: [URLQueryItem]

    @objc public init(baseURL: URL, apiKey: String, uuid: String, appVersion: String, networkQueue: NetworkQueue) {
        self.baseURL = baseURL

        var queryItems = [URLQueryItem]()
        queryItems.append(URLQueryItem(name: "key", value: apiKey))
        queryItems.append(URLQueryItem(name: "app_uid", value: uuid))
        queryItems.append(URLQueryItem(name: "app_ver", value: appVersion))
        queryItems.append(URLQueryItem(name: "version", value: "2"))
        self.defaultQueryItems = queryItems

        self.networkQueue = networkQueue
    }

    @objc public convenience init(baseURL: URL, apiKey: String, uuid: String, appVersion: String) {
        self.init(baseURL: baseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, networkQueue: NetworkQueue())
    }
}
