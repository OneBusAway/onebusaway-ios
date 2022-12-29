//
//  OBAService.swift
//  OBAKitCore
//
//  Created by Alan Chu on 12/28/22.
//

import Foundation
import os.log

public actor RESTAPIService {
    public struct Configuration {
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

    public let configuration: Configuration

    private let logger = Logger()
    nonisolated let dataLoader: URLDataLoader
    nonisolated let urlBuilder: RESTAPIURLBuilder
    nonisolated let decoder: JSONDecoder

    public init(_ configuration: Configuration, dataLoader: URLDataLoader = URLSession.shared) {
        self.configuration = configuration
        self.dataLoader = dataLoader
        self.urlBuilder = RESTAPIURLBuilder(baseURL: configuration.baseURL, defaultQueryItems: configuration.defaultQueryItems)
        self.decoder = JSONDecoder.RESTDecoder(regionIdentifier: configuration.regionIdentifier)
    }

    // MARK: - Common API handlers -

    func logError(_ response: URLResponse?, _ description: String) {
        let urlString: String = response?.url?.absoluteString ?? "(unknown url)"
        logger.error("\(urlString): \(description)")
    }

    // MARK: - URL Builders -

    nonisolated func generateURL(path: String, params: [String: Any]? = nil) -> URL {
        let urlString = joinBaseURLToPath(path)
        let queryParamString = buildQueryParams(params)
        let fullURLString = String(format: "%@?%@", urlString, queryParamString)

        return URL(string: fullURLString)!
    }

    private nonisolated func joinBaseURLToPath(_ path: String) -> String {
        let baseURLString = configuration.baseURL.absoluteString

        if baseURLString.hasSuffix("/") && path.hasPrefix("/") {
            return baseURLString + String(path.dropFirst())
        }
        else if !baseURLString.hasSuffix("/") && !path.hasPrefix("/") {
            return String(format: "%@/%@", baseURLString, path)
        }
        else {
            return baseURLString + path
        }
    }

    /// Takes in a hash of params and this object's default query items, and produces a list of `&`-separated `key=value` pairs.
    /// - Parameter params: Additional query parameters having to do with the in-flight API call.
    private nonisolated func buildQueryParams(_ params: [String: Any]? = nil) -> String {
        let allQueryItems: [URLQueryItem] = NetworkHelpers.dictionary(toQueryItems: params ?? [:]) + configuration.defaultQueryItems
        return allQueryItems.compactMap { queryItem in
            guard
                let key = queryItem.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                let value = queryItem.value?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            else {
                return nil
            }

            return String(format: "%@=%@", key, value)
        }.joined(separator: "&")
    }
}
