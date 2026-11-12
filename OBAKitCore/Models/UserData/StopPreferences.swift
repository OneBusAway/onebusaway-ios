//
//  StopPreferences.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

public enum StopSort: String, Codable {
    case time, route
}

/// Controls which arrivals/departures are displayed based on real-time data availability.
public enum ArrivalDepartureFilter: String, Codable, CaseIterable {
    case all
    case estimatedOnly
    case scheduledOnly
}

public extension ArrivalDepartureFilter {
    /// The filter in effect: the rider's choice saved in `userDefaults` when it
    /// is valid, or the white-label `brandDefault`. In the app, read
    /// `CoreApplication.effectiveArrivalDepartureFilter`; this is for code that
    /// has only the app-group suite, such as an App Intent. Main actor, as
    /// `CoreAppConfig`, which owns the key, is.
    @MainActor
    static func effective(in userDefaults: UserDefaults, brandDefault: ArrivalDepartureFilter) -> ArrivalDepartureFilter {
        if let saved = userDefaults.string(forKey: CoreAppConfig.arrivalDepartureFilterUserDefaultsKey),
           let filter = ArrivalDepartureFilter(rawValue: saved) {
            return filter
        }
        return brandDefault
    }
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
