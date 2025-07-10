//
//  APIService.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import os.log

public protocol APIService {
    var configuration: APIServiceConfiguration { get }
    var dataLoader: URLDataLoader { get }
    var logger: os.Logger { get }

    /// - parameter dataLoader: For mocking network requests. Use `URLSession.shared` for production cases.
    init(_ configuration: APIServiceConfiguration, dataLoader: URLDataLoader)
}

public struct APIServiceConfiguration {
    let baseURL: URL
    let apiKey: String
    let uuid: String
    let appVersion: String
    let regionIdentifier: Int?

    /// Survey API base URL - different from regular OBA API base URL
      let surveyBaseURL: URL?

    /// Generated query items from the initializer. Include this set of query items with every request you make.
    let defaultQueryItems: [URLQueryItem]

    /// - parameter baseURL: Any queries included in the `baseURL` will be moved to the `defaultQueryItems`.
    /// - parameter surveyBaseURL: Optional survey API base URL. If nil, surveys will be disabled.
    init(baseURL: URL, apiKey: String, uuid: String, appVersion: String, regionIdentifier: Int?, surveyBaseURL: URL? = nil) {
        self.apiKey = apiKey
        self.uuid = uuid
        self.appVersion = appVersion
        self.regionIdentifier = regionIdentifier
        self.surveyBaseURL = surveyBaseURL

        // Add default query items, including the component query of the baseURL.
        var queryItems: [URLQueryItem] = [
            "key": apiKey,
            "app_uid": uuid,
            "app_ver": appVersion,
            "version": "2"
        ].map(URLQueryItem.init(name:value:))

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        if let items = components.queryItems, items.isEmpty == false {
            queryItems.append(contentsOf: items)
        }

        self.defaultQueryItems = queryItems

        // We've successfully saved off any query items that were a part of the baseURL.
        // So we nil out the query here so that we can safely append path components to
        // the baseURL elsewhere.
        components.query = nil

        self.baseURL = components.url!
    }
}
