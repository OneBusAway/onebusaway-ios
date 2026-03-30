//
//  BookmarkSpotlightIndexer.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreSpotlight
import OBAKitCore

/// Keeps the iOS Spotlight index in sync with the user's bookmarks.
///
/// Call `indexAll(_:)` on app launch and whenever bookmarks change.
/// Tapping a Spotlight result delivers an `NSUserActivity` with
/// `activityType == CSSearchableItemActionType`, which the existing
/// deep-link handler in `AppDelegate` already knows how to route.
final class BookmarkSpotlightIndexer {

    // MARK: - Constants

    /// Domain prefix used to namespace all OBA Spotlight items so we can
    /// delete them cleanly without touching items from other apps.
    static let domainIdentifier = "org.onebusaway.iphone.bookmark"

    // MARK: - Public API

    /// Replaces the entire Spotlight index for bookmarks with the supplied list.
    /// Safe to call on any thread — work is dispatched internally.
    static func indexAll(_ bookmarks: [Bookmark]) {
        let items = bookmarks.map { searchableItem(for: $0) }

        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                Logger.error("Spotlight indexing failed: \(error)")
            }
        }
    }

    /// Adds or updates a single bookmark in the Spotlight index.
    static func index(_ bookmark: Bookmark) {
        let item = searchableItem(for: bookmark)
        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error {
                Logger.error("Spotlight index update failed for bookmark \(bookmark.id): \(error)")
            }
        }
    }

    /// Removes a single bookmark from the Spotlight index.
    static func remove(_ bookmark: Bookmark) {
        let identifier = spotlightID(for: bookmark)
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [identifier]) { error in
            if let error {
                Logger.error("Spotlight removal failed for bookmark \(bookmark.id): \(error)")
            }
        }
    }

    /// Removes all OBA bookmark items from the Spotlight index.
    static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { error in
            if let error {
                Logger.error("Spotlight removeAll failed: \(error)")
            }
        }
    }

    // MARK: - Private helpers

    private static func spotlightID(for bookmark: Bookmark) -> String {
        "\(domainIdentifier).\(bookmark.id.uuidString)"
    }

    private static func searchableItem(for bookmark: Bookmark) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)

        // Primary display name — what the user sees in Spotlight results.
        attributes.title = bookmark.name

        // Subtitle line — route info for trip bookmarks, stop ID otherwise.
        if let route = bookmark.routeShortName, let headsign = bookmark.tripHeadsign {
            attributes.contentDescription = "\(route) – \(headsign)"
        } else {
            attributes.contentDescription = OBALoc(
                "bookmark_spotlight.stop_id_fmt",
                value: "Stop %@",
                comment: "Spotlight result subtitle showing the stop ID. e.g. 'Stop 1_75403'"
            ).replacingOccurrences(of: "%@", with: bookmark.stopID)
        }

        // Keywords improve discoverability when the user types partial text.
        var keywords = [bookmark.name, bookmark.stopID]
        if let route = bookmark.routeShortName { keywords.append(route) }
        if let headsign = bookmark.tripHeadsign { keywords.append(headsign) }
        attributes.keywords = keywords

        // Location — lets Spotlight surface the result when the user is nearby.
        attributes.latitude = bookmark.stop.coordinate.latitude as NSNumber
        attributes.longitude = bookmark.stop.coordinate.longitude as NSNumber

        return CSSearchableItem(
            uniqueIdentifier: spotlightID(for: bookmark),
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
    }
}
