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

extension Array {
    /// Performs a binary search.
    /// - important: The array must be sorted.
    /// - parameter sortedBy: Which key the array is sorted by.
    /// - parameter element: The element to look for.
    /// - returns: The element and its index, if found. `nil` if not found.
    func binarySearch<T: Comparable>(sortedBy keyPath: KeyPath<Element, T>, element: T) -> (index: Int, element: Element)? {
        var lowerBound = 0
        var upperBound = self.count
        while lowerBound < upperBound {
            let midIndex = lowerBound + (upperBound - lowerBound) / 2
            if self[midIndex][keyPath: keyPath] == element {
                return (midIndex, self[midIndex])
            } else if self[midIndex][keyPath: keyPath] < element {
                lowerBound = midIndex + 1
            } else {
                upperBound = midIndex
            }
        }
        return nil
    }
}
