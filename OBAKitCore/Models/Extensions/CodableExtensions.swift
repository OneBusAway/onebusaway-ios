//
//  CodableExtensions.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

extension KeyedDecodingContainer {

    /// Decodes an optional URL where the underlying value may either be
    /// nil, a blank string, or a valid URL, for the given key, if present.
    ///
    /// This method returns `nil` if the container does not have a value
    /// associated with `key`, or if the value is null or garbage (e.g. a blank string). The difference between
    /// these states can be distinguished with a `contains(_:)` call.
    ///
    /// - parameter key: The key that the decoded value is associated with.
    /// - returns: A decoded value of the requested type, or `nil` if the
    ///   `Decoder` does not have an entry associated with the given key, or if
    ///   the value is a null value.
    /// - throws: `DecodingError.typeMismatch` if the encountered encoded value
    ///   is not convertible to `String`.
    func decodeGarbageURL(forKey key: Self.Key) throws -> URL? {
        let rawStr = try decodeIfPresent(String.self, forKey: key)
        
        // First check if the string is nil
        guard let str = rawStr else {
            return nil
        }
        
        // Check if string is blank (empty or whitespace only)
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }
        
        // Try to create URL from the original string
        guard let url = URL(string: str) else {
            return nil
        }
        
        // Validate the URL has either a scheme or is a path
        if url.scheme != nil || str.hasPrefix("/") {
            return url
        }
        
        // If we get here, it's a garbage URL like "not a url" or whitespace
        return nil
    }
}
