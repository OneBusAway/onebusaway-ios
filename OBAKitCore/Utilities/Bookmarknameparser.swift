//
//  BookmarkNameParser.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Utility for parsing bookmark names in the format "ROUTE - HEADSIGN"
public struct BookmarkNameParser {
    /// Extracts route short name and headsign from bookmark name.
    ///
    /// Example: "36 - Othello Station N Beacon Hill" → ("36", "Othello Station N Beacon Hill")
    ///
    /// - Parameter name: The full bookmark name
    /// - Returns: A tuple containing (routeShortName, routeHeadsign)
    public static func parse(_ name: String) -> (routeShortName: String, routeHeadsign: String) {
        guard let dashIndex = name.firstIndex(of: "-") else {
            return (name, "")
        }
        let routeShortName = String(name[..<dashIndex]).trimmingCharacters(in: .whitespaces)
        let afterDash = name.index(after: dashIndex)
        let routeHeadsign = String(name[afterDash...]).trimmingCharacters(in: .whitespaces)
        return (routeShortName, routeHeadsign)
    }
    /// Extracts only the route short name from a bookmark name.
    ///
    /// - Parameter name: The full bookmark name
    /// - Returns: The route short name (e.g., "36")
    public static func routeShortName(from name: String) -> String {
        return parse(name).routeShortName
    }
    /// Extracts only the route headsign from a bookmark name.
    ///
    /// - Parameter name: The full bookmark name
    /// - Returns: The route headsign (e.g., "Othello Station N Beacon Hill")
    public static func routeHeadsign(from name: String) -> String {
        return parse(name).routeHeadsign
    }
}
