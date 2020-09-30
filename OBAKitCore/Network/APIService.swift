//
//  APIService.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// The core class for interacting with the OBA REST API. Treat this as an abstract class, and instead interact with its subclasses.
///
/// This class is responsible for managing the base URL for the OBA REST API server,
/// the network queue for in-flight operations, and the query parameters that are
/// common to every request.
public class APIService: NSObject {
    let baseURL: URL
    let networkQueue: OperationQueue
    let defaultQueryItems: [URLQueryItem]
    let dataLoader: URLDataLoader

    /// Creates a new instance of `APIService`.
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

    /// Creates a new instance of APIService.
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
