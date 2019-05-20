//
//  FoundationExtensions.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/22/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import Foundation

public extension Sequence where Element == String {

    /// Performs a localized case insensitive sort on the receiver.
    ///
    /// - Returns: A localized, case-insensitive sorted Array.
    func localizedCaseInsensitiveSort() -> [Element] {
        return sorted { (s1, s2) -> Bool in
            return s1.localizedCaseInsensitiveCompare(s2) == .orderedAscending
        }
    }
}

public extension UserDefaults {

    /// Returns a typed object for `key`, if it exists.
    ///
    /// - Parameters:
    ///   - type: The type of the object to return.
    ///   - key: The key for the object.
    /// - Returns: The object, if it exists in the user defaults. Otherwise `nil`.
    /// - Throws: An exception from force-unwrapping if you passed in the wrong type T.
    func object<T>(type: T.Type, forKey key: String) throws -> T? {
        guard let obj = object(forKey: key) else {
            return nil
        }

        return (obj as! T)
    }
}
