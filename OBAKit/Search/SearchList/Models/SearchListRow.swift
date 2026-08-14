//
//  SearchListRow.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 07/03/2026.
//

import Foundation
import MapKit
import UIKit
import OBAKitCore

struct SearchListRow: Identifiable {
    enum Accessory {
        case disclosureIndicator
        case none
    }

    enum Kind {
        case quickSearch(SearchType)
        /// Carries the stop's id for the same reason `searchResult` does: recent
        /// stops are rendered in a `ForEach`, and two stops on opposite sides of a
        /// corner share a name.
        case recentStop(id: String)
        /// Carries the bookmark's id for the same reason `recentStop` does: a
        /// bookmark's default name is its stop's name, so two bookmarks on
        /// opposite sides of one street would otherwise share a row id.
        case bookmark(id: String)
        case placemark(MKMapItem)
        /// A row in a disambiguation list. Carries the underlying model's id
        /// because titles are not identity — two stops on opposite sides of the
        /// same corner share a name, and two agencies can both run a route "1".
        /// Deriving the row id from the title alone collides in exactly the case
        /// a disambiguation list exists to handle.
        case searchResult(id: String)
        case clearRecents
        case loading
        case noResults
        case error(String, systemImage: String)

        var isPlacemark: Bool {
            if case .placemark = self { return true }
            return false
        }

        var stableIdentifier: String {
            switch self {
            case .quickSearch(let type):
                return "quickSearch-\(type.rawValue)"
            case .recentStop(let id):
                return "recentStop-\(id)"
            case .bookmark(let id):
                return "bookmark-\(id)"
            case .placemark(let item):
                let coord = item.placemark.coordinate
                return "placemark-\(coord.latitude)-\(coord.longitude)"
            case .searchResult(let id):
                return "searchResult-\(id)"
            case .clearRecents:
                return "clearRecents"
            case .loading:
                return "loading"
            case .noResults:
                return "noResults"
            case .error(let message, _):
                return "error-\(message)"
            }
        }
    }

    enum Icon {
        case system(String)
        case uiImage(UIImage)
    }

    let id: String
    let kind: Kind
    let title: String?
    let attributedTitle: NSAttributedString?
    let subtitle: String?
    let icon: Icon?
    let accessory: Accessory
    let action: (() -> Void)?

    init(
        kind: Kind,
        title: String? = nil,
        attributedTitle: NSAttributedString? = nil,
        subtitle: String? = nil,
        icon: Icon? = nil,
        accessory: Accessory = .none,
        action: (() -> Void)? = nil
    ) {
        self.id = "\(kind.stableIdentifier)-\(title ?? "")"
        self.kind = kind
        self.title = title
        self.attributedTitle = attributedTitle
        self.subtitle = subtitle
        self.icon = icon
        self.accessory = accessory
        self.action = action
    }
}

// MARK: - Placemark Row Building
extension SearchListRow {

    static func subtitleForMapItem(_ application: Application, _ mapItem: MKMapItem) -> String? {
        var parts: [String] = []

        // Distance
        if let currentLocation = application.locationService.currentLocation,
            let destination = mapItem.placemark.location {
            let distance = currentLocation.distance(from: destination)
            let formatted = application.formatters.distanceFormatter.string(fromDistance: distance)
            parts.append(formatted)
        }

        // Address
        if #available(iOS 26.0, *) {
            if let short = mapItem.address?.shortAddress {
                parts.append(short)
            }
        } else {
            let pm = mapItem.placemark
            let addressParts = [pm.subThoroughfare, pm.thoroughfare, pm.locality, pm.subAdministrativeArea, pm.administrativeArea, pm.postalCode]
            let address = addressParts.compactMap { $0 }.joined(separator: " ")
            if !address.isEmpty { parts.append(address) }
        }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    static func systemImageForMapItem(_ mapItem: MKMapItem) -> Icon {
        if let poi = mapItem.pointOfInterestCategory {
            return .system(poi.symbolName)
        }
        return .system("mappin")
    }
}

// MARK: - Stop Row Building

extension SearchListRow {

    /// The standard `SearchListRow` for a stop: stop glyph, name, and a
    /// "distance • direction" subtitle.
    ///
    /// Used by the search results sheet (`SearchResultRow`). The home sheet's
    /// nearby and recent sections deliberately do **not** use this — they render
    /// `HomeStopRow`, which uses the squircle transport glyph to match the
    /// bookmark cards it sits beside. Keep this in step with the search list's
    /// placemark rows, not with the home sheet.
    ///
    /// `kind` is a parameter rather than fixed because the caller owns row
    /// identity — the same stop can legitimately appear in two sections at once.
    @MainActor
    static func stop(
        _ stop: Stop,
        application: Application,
        kind: Kind,
        onSelect: @escaping () -> Void
    ) -> SearchListRow {
        SearchListRow(
            kind: kind,
            title: stop.name,
            subtitle: stopSubtitle(application, stop),
            icon: .uiImage(Icons.stop),
            accessory: .disclosureIndicator,
            action: onSelect
        )
    }

    /// Direction plus distance from the user, mirroring what the placemark rows
    /// in the search list already show. Distance is dropped when there's no fix.
    @MainActor
    static func stopSubtitle(_ application: Application, _ stop: Stop) -> String? {
        var parts: [String] = []

        if let currentLocation = application.locationService.currentLocation {
            let distance = currentLocation.distance(from: stop.location)
            parts.append(application.formatters.distanceFormatter.string(fromDistance: distance))
        }

        if let direction = Formatters.adjectiveFormOfCardinalDirection(stop.direction), !direction.isEmpty {
            parts.append(direction)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}
