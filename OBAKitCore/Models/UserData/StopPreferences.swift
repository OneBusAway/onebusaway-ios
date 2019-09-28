//
//  StopPreferences.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 8/13/19.
//

import Foundation

public enum StopSort: String, Codable {
    case time, route
}

/// A model that represents the user's preferences for a particular `Stop`. These preferences are for things like sort order and hidden routes.
public struct StopPreferences: Codable {
    public var sortType: StopSort
    public var hiddenRoutes: [RouteID]

    public init() {
        self.sortType = .time
        self.hiddenRoutes = [RouteID]()
    }

    public init(sortType: StopSort, hiddenRoutes: [RouteID]) {
        self.sortType = sortType
        self.hiddenRoutes = hiddenRoutes
    }

    /// Returns `true` if the specified `RouteID` should be hidden, and `false` otherwise.
    /// - Parameter id: The `RouteID`.
    public func isRouteIDHidden(_ id: RouteID) -> Bool {
        hiddenRoutes.contains(id)
    }

    /// Toggles whether the specified `RouteID` is hidden or visible.
    /// - Parameter id: The `RouteID` to toggle.
    public mutating func toggleRouteIDHidden(_ id: RouteID) {
        if let index = hiddenRoutes.firstIndex(of: id) {
            hiddenRoutes.remove(at: index)
        }
        else {
            hiddenRoutes.append(id)
        }
    }

    /// `true` if this `StopPreferences` notes that certain `Route`s should be hidden.
    public var hasHiddenRoutes: Bool {
        hiddenRoutes.count > 0
    }
}
