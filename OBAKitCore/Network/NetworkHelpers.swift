//
//  NetworkHelpers.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
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

    /// RFC 3986 "unreserved" characters. Form values must be escaped against this set, not
    /// `.urlQueryAllowed` — the latter leaves `&`, `+`, `;`, and `=` raw, which truncates a
    /// free-text value at the first `&`, turns `+` into a space server-side, and injects
    /// bogus params from a stray `=`. Rider-authored ghost-bus comments, trip headsigns
    /// ("15th Ave & Broadway"), and device descriptions all carry those characters.
    private static let formUnreservedCharacters: CharacterSet = {
        var unreserved = CharacterSet.alphanumerics
        unreserved.insert(charactersIn: "-._~")
        return unreserved
    }()

    public class func dictionary(toHTTPBodyData dict: [String: Any]) -> Data {
        return dict.map { (k, v) -> String in
            let keyStr = k.addingPercentEncoding(withAllowedCharacters: formUnreservedCharacters) ?? k
            let valueStr = "\(v)".addingPercentEncoding(withAllowedCharacters: formUnreservedCharacters) ?? "\(v)"
            return "\(keyStr)=\(valueStr)"
        }.joined(separator: "&").data(using: .utf8)!
    }
}
