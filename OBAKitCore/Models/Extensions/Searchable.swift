//
//  Searchable.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

// MARK: - Protocol

public protocol Searchable {
    func matchesQuery(_ query: String?) -> Bool
}

// MARK: - Models

extension Bookmark: Searchable {
    public func matchesQuery(_ query: String?) -> Bool {
        guard let query = query else {
            return true
        }

        if let routeShortName = routeShortName, routeShortName.localizedCaseInsensitiveContains(query) {
            return true
        }

        if let tripHeadsign = tripHeadsign, tripHeadsign.localizedCaseInsensitiveContains(query) {
            return true
        }

        return stop.matchesQuery(query)
    }
}

extension Route: Searchable {
    public func matchesQuery(_ query: String?) -> Bool {
        guard let query = query else {
            return true
        }

        if let routeDescription = routeDescription, routeDescription.localizedCaseInsensitiveContains(query) {
            return true
        }

        if let longName = longName, longName.localizedCaseInsensitiveContains(query) {
            return true
        }

        if shortName.localizedCaseInsensitiveContains(query) {
            return true
        }

        return false
    }
}

extension Stop: Searchable {
    public func matchesQuery(_ query: String?) -> Bool {
        guard let query = query else {
            return true
        }

        if name.localizedCaseInsensitiveContains(query) {
            return true
        }

        // swiftlint:disable for_where

//        for route in routes {
//            if route.matchesQuery(query) {
//                return true
//            }
//        }

        // swiftlint:enable for_where

        return false
    }
}
