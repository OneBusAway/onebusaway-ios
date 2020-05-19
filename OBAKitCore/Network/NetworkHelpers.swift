//
//  NetworkHelpers.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 2/7/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import Foundation

/// Helper functions for creating network requests.
class NetworkHelpers: NSObject {

    /// Creates an array of `URLQueryItem`s from a dictionary.
    ///
    /// - Parameter dict: The dictionary to convert
    /// - Returns: An array of `URLQueryItem`s.
    public class func dictionary(toQueryItems dict: [String: Any]) -> [URLQueryItem] {
        var queryArgs = [URLQueryItem]()

        for (k, v) in dict {
            let item = URLQueryItem(name: k, value: "\(v)")
            queryArgs.append(item)
        }
        return queryArgs
    }

    public class func escapePathVariable(_ pathVariable: String) -> String {
        // Apparently -stringByAddingPercentEncodingWithAllowedCharacters: won't remove
        // '/' characters from paths, so we get to do that manually here. Boo.
        // https://github.com/OneBusAway/onebusaway-iphone/issues/817
        return pathVariable
                .addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed)!
                .replacingOccurrences(of: "/", with: "%2F")
    }

    public class func dictionary(toHTTPBodyData dict: [String: Any]) -> Data {
        return dict.map { (k, v) -> String in
            let keyStr = k.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)!
            let valueStr = "\(v)".addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)!
            return "\(keyStr)=\(valueStr)"
        }.joined(separator: "&").data(using: .utf8)!
    }
}
