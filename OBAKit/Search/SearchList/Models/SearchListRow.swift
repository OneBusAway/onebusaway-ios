//
//  SearchListRow.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 07/03/2026.
//

import Foundation
import MapKit

struct SearchListRow: Identifiable {
    enum Accessory {
        case disclosureIndicator
        case none
    }

    enum Kind {
        case quickSearch(SearchType)
        case recentStop
        case bookmark
        case placemark(MKMapItem)
        case clearRecents
        case loading
        case noResults
        case error(String, systemImage: String)
    }

    enum Icon {
        case system(String)
        case uiImage(UIImage)
    }

    let id: UUID
    let kind: Kind
    let title: String?
    let attributedTitle: NSAttributedString?
    let subtitle: String?
    let icon: Icon?
    let accessory: Accessory
    let action: (() -> Void)?

    init(
        id: UUID = UUID(),
        kind: Kind,
        title: String? = nil,
        attributedTitle: NSAttributedString? = nil,
        subtitle: String? = nil,
        icon: Icon? = nil,
        accessory: Accessory = .none,
        action: (() -> Void)? = nil
    ) {
        self.id = id
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
