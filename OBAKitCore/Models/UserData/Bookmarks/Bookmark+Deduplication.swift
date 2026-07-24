//
//  Bookmark+Deduplication.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public extension Sequence where Element == Bookmark {
    /// Maps each stop to its winning bookmark (last wins). Shared by the map and
    /// SwiftUI paths so precedence stays identical.
    func dedupedByStopID() -> [StopID: Bookmark] {
        var result = [StopID: Bookmark]()
        for bookmark in self {
            result[bookmark.stopID] = bookmark
        }
        return result
    }
}
