//
//  StopEntity.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import AppIntents
import CoreSpotlight
import OBAKitCore

/// A transit stop, as Shortcuts, Siri and Spotlight see it (#1555).
///
/// Everything stored is a plain value, so the entity is `Sendable`; the stop's
/// coordinates are kept as `Double`s, never a `CLLocation`. A stop the app has
/// no copy of (see `StopEntityMapping.entities(forIdentifiers:bookmarks:recentStops:)`)
/// has only `regionID` and `stopID`, and is titled with its stop id.
///
/// App Entity types are extracted off the main actor; OBAKit defaults to `@MainActor`.
/// Strings come from `AppIntents.strings`; see `TrackBookmarkIntent` for why.
nonisolated public struct StopEntity: IndexedEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("stop_entity.type_name", defaultValue: "Stop", table: "AppIntents")
    )
    public static let defaultQuery = StopEntityQuery()

    let regionID: Int
    let stopID: StopID
    let name: String?
    let code: String?
    let subtitle: String?
    let latitude: Double?
    let longitude: Double?

    public var id: String {
        StopEntityMapping.identifier(regionID: regionID, stopID: stopID)
    }

    var destination: AppLinksRouter.StopDestination {
        AppLinksRouter.StopDestination(stopID: stopID, regionID: regionID)
    }

    public var displayRepresentation: DisplayRepresentation {
        let title = name ?? String(
            format: OBALoc("stop_entity.fallback_title_fmt", value: "Stop %@", comment: "Title of a transit stop in Shortcuts and Siri when the app has no name for it. The parameter is the stop's ID, such as 1_75403."),
            stopID
        )
        return DisplayRepresentation(title: "\(title)", subtitle: subtitle.map { "\($0)" })
    }

    /// Lets Spotlight find the stop by its code and place it on a map. These
    /// are the stop's own coordinates, which are public; never the rider's.
    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        if let code {
            attributes.keywords = [code]
        }
        if let latitude, let longitude {
            attributes.latitude = NSNumber(value: latitude)
            attributes.longitude = NSNumber(value: longitude)
        }
        return attributes
    }
}

/// Reads bookmarks and recent stops from the app-group suite, like
/// `BookmarkEntityQuery`, never `Application`. Search covers those stops only.
/// Searching every cached stop needs the cache to store names and codes in
/// their own columns, which is #1555's region sync (PR A).
nonisolated public struct StopEntityQuery: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [StopEntity.ID]) async throws -> [StopEntity] {
        guard let defaults = Self.appGroupDefaults() else { return [] }
        let store = UserDefaultsStore(userDefaults: defaults)
        return StopEntityMapping.entities(forIdentifiers: identifiers, bookmarks: store.bookmarks, recentStops: store.recentStops)
    }

    /// Without these the Shortcuts picker is empty.
    public func suggestedEntities() async throws -> [StopEntity] {
        suggested()
    }

    public func entities(matching string: String) async throws -> [StopEntity] {
        StopEntityMapping.matching(string, in: suggested())
    }

    private func suggested() -> [StopEntity] {
        guard let defaults = Self.appGroupDefaults() else { return [] }
        let store = UserDefaultsStore(userDefaults: defaults)
        let regionID = defaults.object(forKey: RegionsService.currentRegionIdentifierUserDefaultsKey) as? Int
        return StopEntityMapping.suggested(bookmarks: store.bookmarks, recentStops: store.recentStops, regionID: regionID)
    }

    private static func appGroupDefaults() -> UserDefaults? {
        guard let suite = Bundle.main.appGroup,
              let defaults = UserDefaults(suiteName: suite) else {
            Logger.error("Stop entity query: app group UserDefaults unavailable; offering no stops.")
            return nil
        }
        return defaults
    }
}

/// The stop entity's rules, as pure functions so they can be tested without
/// the app-group suite.
nonisolated enum StopEntityMapping {
    /// Keeps a busy stop's subtitle short. Past it, `Formatters` adds its
    /// translated "+ N more".
    static let subtitleRouteLimit = 5

    /// At most this many search results, so a short query doesn't flood the picker.
    static let searchResultLimit = 20

    /// The entity's id, and the stop activity's `persistentIdentifier`. Saved
    /// shortcuts and Spotlight store it, so changing it orphans what they hold.
    static func identifier(regionID: Int, stopID: StopID) -> String {
        "region_\(regionID)_stop_\(stopID)"
    }

    /// Splits at the first `_stop_` after the region, so a stop id that itself
    /// contains `_stop_` survives.
    static func destination(fromIdentifier identifier: String) -> AppLinksRouter.StopDestination? {
        let prefix = "region_"
        guard identifier.hasPrefix(prefix) else { return nil }
        let rest = identifier.dropFirst(prefix.count)
        guard let separator = rest.range(of: "_stop_"),
              let regionID = Int(rest[..<separator.lowerBound]) else { return nil }
        let stopID = rest[separator.upperBound...]
        guard !stopID.isEmpty else { return nil }
        return AppLinksRouter.StopDestination(stopID: String(stopID), regionID: regionID)
    }

    static func entity(for stop: Stop, regionID: Int) -> StopEntity {
        // `routes` is nil on a stop decoded from the REST API without them.
        let parts = [
            Formatters.adjectiveFormOfCardinalDirection(stop.direction),
            Formatters.formattedRoutes(stop.routes ?? [], limit: subtitleRouteLimit)
        ].compactMap { $0 }

        return StopEntity(
            regionID: regionID,
            stopID: stop.id,
            name: stop.name,
            // GTFS leaves `stop_code` blank for stops with no code shown to riders.
            code: stop.code.isEmpty ? nil : stop.code,
            subtitle: parts.isEmpty ? nil : parts.joined(separator: " • "),
            latitude: stop.location.coordinate.latitude,
            longitude: stop.location.coordinate.longitude
        )
    }

    /// Bookmarked stops in store order, then recent ones, each stop once, from
    /// `regionID` only. A trip bookmark contributes its stop.
    static func suggested(bookmarks: [Bookmark], recentStops: [Stop], regionID: Int?) -> [StopEntity] {
        guard let regionID else { return [] }
        let bookmarked = bookmarks.filter { $0.regionIdentifier == regionID }.map(\.stop)
        let recent = recentStops.filter { $0.regionIdentifier == regionID }

        // Stores written before `addRecentStop` deduplicated can hold a stop twice.
        var seen = Set<StopID>()
        return (bookmarked + recent)
            .filter { seen.insert($0.id).inserted }
            .map { entity(for: $0, regionID: regionID) }
    }

    /// Looks each id up among every bookmark and recent stop, in any region, so
    /// a shortcut saved in another region still names its stop and
    /// `Application.queueOrOpenStop(_:)` can say why it won't open. An id the
    /// app has no copy of still opens, as a fallback entity titled with its
    /// stop id. An id that doesn't parse is dropped.
    static func entities(forIdentifiers identifiers: [String], bookmarks: [Bookmark], recentStops: [Stop]) -> [StopEntity] {
        identifiers.compactMap { identifier in
            guard let destination = destination(fromIdentifier: identifier) else {
                Logger.warn("Stop entity id \(identifier) doesn't name a region and stop; dropping it.")
                return nil
            }

            let stored = bookmarks.first { $0.regionIdentifier == destination.regionID && $0.stopID == destination.stopID }?.stop
                ?? recentStops.first { $0.regionIdentifier == destination.regionID && $0.id == destination.stopID }

            if let stored {
                return entity(for: stored, regionID: destination.regionID)
            }
            return StopEntity(regionID: destination.regionID, stopID: destination.stopID, name: nil, code: nil, subtitle: nil, latitude: nil, longitude: nil)
        }
    }

    /// A name matches anywhere, ignoring case and diacritics (KiedyBus riders
    /// search Polish names). A code matches from its start.
    static func matching(_ query: String, in entities: [StopEntity]) -> [StopEntity] {
        let hits = entities.filter { entity in
            if let name = entity.name, name.localizedStandardContains(query) {
                return true
            }
            if let code = entity.code, code.range(of: query, options: [.anchored, .caseInsensitive]) != nil {
                return true
            }
            return false
        }
        return Array(hits.prefix(searchResultLimit))
    }
}
