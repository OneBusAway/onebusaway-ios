//
//  Collections.swift
//  OBAAppKit
//
//  Created by Aaron Brethorst on 11/22/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
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
