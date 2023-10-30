//
//  Collections.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

extension Set {

    /// Returns all objects contained within the receiver.
    public var allObjects: [Element] {
        return map {$0}
    }
}

extension Sequence {

    /// Filters by type
    ///
    /// - Parameter type: The type to filter the receiver by.
    /// - Returns: An array of objects that conform to the passed-in type.
    public func filter<T>(type: T.Type) -> [T] {
        return compactMap {$0 as? T}
    }

    /// Sorts by key path.
    public func sorted<T: Comparable>(by keyPath: KeyPath<Element, T>) -> [Element] {
        return sorted { a, b in
            return a[keyPath: keyPath] < b[keyPath: keyPath]
        }
    }
}

extension Array where Element: Hashable {
    /// Removes duplicates (based on `Hashable`) while preserving order.
    public var uniqued: Array {
        var result: [Element] = []
        var addedItems: Set<Element> = []
        for item in self where !addedItems.contains(item) {
            result.append(item)
            addedItems.insert(item)
        }
        return result
    }
}
