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

    /// Generated query items from the initializer. Include this set of query items with every request you make.
    let defaultQueryItems: [URLQueryItem]

    /// - parameter baseURL: Any queries included in the `baseURL` will be moved to the `defaultQueryItems`.
    init(baseURL: URL, apiKey: String, uuid: String, appVersion: String, regionIdentifier: Int?) {
        self.apiKey = apiKey
        self.uuid = uuid
        self.appVersion = appVersion
        self.regionIdentifier = regionIdentifier

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

/// The core class for interacting with the OBA REST API. Treat this as an abstract class, and instead interact with its subclasses.
///
/// This class is responsible for managing the base URL for the OBA REST API server,
/// the network queue for in-flight operations, and the query parameters that are
/// common to every request.
public class _APIService: NSObject {
    let baseURL: URL
    let networkQueue: OperationQueue
    let defaultQueryItems: [URLQueryItem]
    let dataLoader: URLDataLoader

    /// Creates a new instance of `_APIService`.
    /// - Parameters:
    ///   - baseURL: The base URL for the service you will be using.
    ///   - apiKey: The API key for the service you will be using. Passed along as `key` in query params.
    ///   - uuid: A unique, anonymous user ID.
    ///   - appVersion: The version of the app making the request.
    ///   - networkQueue: The queue on which all network operations will be performed.
    ///   - dataLoader: The object used to perform network operations. A protocol facade is provided here to simplify testing.
    public init(baseURL: URL, apiKey: String, uuid: String, appVersion: String, networkQueue: OperationQueue, dataLoader: URLDataLoader) {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!

        var queryItemsDict = [String: URLQueryItem]()
        queryItemsDict["key"] = URLQueryItem(name: "key", value: apiKey)
        queryItemsDict["app_uid"] = URLQueryItem(name: "app_uid", value: uuid)
        queryItemsDict["app_ver"] = URLQueryItem(name: "app_ver", value: appVersion)
        queryItemsDict["version"] = URLQueryItem(name: "version", value: "2")

        if let items = components.queryItems, items.count > 0 {
            for qi in items {
                queryItemsDict[qi.name] = qi
            }
        }
        self.defaultQueryItems = Array(queryItemsDict.values)

        // We've successfully saved off any query items that were a part of the baseURL.
        // So we nil out the query here so that we can safely append path components to
        // the baseURL elsewhere.
        components.query = nil

        self.baseURL = components.url!

        self.networkQueue = networkQueue

        self.dataLoader = dataLoader
    }

    /// Creates a new instance of _APIService.
    /// - Parameters:
    ///   - baseURL: The base URL for the service you will be using.
    ///   - apiKey: The API key for the service you will be using. Passed along as `key` in query params.
    ///   - uuid: A unique, anonymous user ID.
    ///   - appVersion: The version of the app making the request.
    public convenience init(baseURL: URL, apiKey: String, uuid: String, appVersion: String) {
        self.init(baseURL: baseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, networkQueue: OperationQueue(), dataLoader: URLSession.shared)
    }

    deinit {
        networkQueue.cancelAllOperations()
    }

    // MARK: - Internal Helpers

    func enqueueOperation(_ operation: Operation) {
        if let requestable = operation as? Requestable, let url = requestable.request.url {
            Logger.info("Enqueuing URL: \(url.absoluteString)")
        }
        networkQueue.addOperation(operation)
    }
}
