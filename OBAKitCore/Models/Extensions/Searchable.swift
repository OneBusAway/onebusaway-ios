//
//  Searchable.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 7/7/19.
//

import Foundation

// MARK: - Protocol

public protocol Searchable {
    func matchesQuery(_ query: String?) -> Bool
}

// MARK: - Models

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

        for route in routes {
            if route.matchesQuery(query) {
                return true
            }
        }

        return false
    }
}
