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
}
