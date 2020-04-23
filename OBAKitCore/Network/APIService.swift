//
//  APIService.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 10/15/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CocoaLumberjackSwift

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
    }

    public convenience init(baseURL: URL, apiKey: String, uuid: String, appVersion: String) {
        self.init(baseURL: baseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, networkQueue: OperationQueue())
    }

    deinit {
        networkQueue.cancelAllOperations()
    }

    // MARK: - Internal Helpers

    func enqueueOperation(_ operation: Operation) {
        if let requestable = operation as? Requestable, let url = requestable.request.url {
            DDLogInfo("Enqueuing URL: \(url.absoluteString)")
        }
        networkQueue.addOperation(operation)
    }
}
