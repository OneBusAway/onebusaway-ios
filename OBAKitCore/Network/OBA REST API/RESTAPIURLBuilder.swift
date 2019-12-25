//
//  RESTAPIURLBuilder.swift
//  OBAKitCore
//
//  Created by Aaron Brethorst on 12/24/19.
//

import Foundation

/// Creates `URL`s for the `RESTAPIService`.
///
/// This class is designed to handle the oddities of different OBA regions' URL schemes without over- or under-escaping paths.
internal class RESTAPIURLBuilder: NSObject {
    private let baseURL: URL
    private let defaultQueryItems: [URLQueryItem]

    init(baseURL: URL, defaultQueryItems: [URLQueryItem]) {
        self.baseURL = baseURL
        self.defaultQueryItems = defaultQueryItems
    }

    public func generateURL(path: String, params: [String: Any]? = nil) -> URL {
        let urlString = joinBaseURLToPath(path)
        let queryParamString = buildQueryParams(params)
        let fullURLString = String(format: "%@?%@", urlString, queryParamString)

        return URL(string: fullURLString)!
    }

    private func joinBaseURLToPath(_ path: String) -> String {
        let baseURLString = baseURL.absoluteString

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
    private func buildQueryParams(_ params: [String: Any]? = nil) -> String {
        let allQueryItems: [URLQueryItem] = NetworkHelpers.dictionary(toQueryItems: params ?? [:]) + defaultQueryItems
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
