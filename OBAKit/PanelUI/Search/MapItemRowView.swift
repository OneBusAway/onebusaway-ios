//
//  MapItemRowView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import MapKit
import OBAKitCore

/// A row view for displaying an MKMapItem with POI icon, name, and distance
struct MapItemRowView: View {
    let mapItem: MKMapItem
    let currentLocation: CLLocation?
    let distanceFormatter: MKDistanceFormatter
    let brandColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // POI Icon Badge
                iconBadge

                VStack(alignment: .leading, spacing: 2) {
                    Text(mapItem.name ?? "Unknown")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var iconBadge: some View {
        let symbolName = mapItem.pointOfInterestCategory?.symbolName ?? "mappin"
        return Image(systemName: symbolName)
            .font(.system(size: 14))
            .foregroundColor(.white)
            .frame(width: 32, height: 32)
            .background(brandColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var subtitleText: String {
        var parts: [String] = []

        // Distance from current location
        if let currentLocation, let destination = mapItem.placemark.location {
            let distance = currentLocation.distance(from: destination)
            parts.append(distanceFormatter.string(fromDistance: distance))
        }

        // Address
        let pm = mapItem.placemark
        let addressParts = [pm.subThoroughfare, pm.thoroughfare, pm.locality]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

        if !addressParts.isEmpty {
            parts.append(addressParts.joined(separator: " "))
        }

        return parts.joined(separator: " • ")
    }
}

// MARK: - POI Category Symbol Names

extension MKPointOfInterestCategory {
    /// Returns an SF Symbol name appropriate for this POI category
    var symbolName: String {
        switch self {
        case .airport: return "airplane"
        case .atm, .bank: return "building.columns"
        case .bakery: return "birthday.cake"
        case .cafe: return "cup.and.saucer"
        case .carRental: return "car"
        case .evCharger: return "bolt.car"
        case .fireStation: return "flame"
        case .fitnessCenter: return "figure.run"
        case .foodMarket: return "cart"
        case .gasStation: return "fuelpump"
        case .hospital: return "cross"
        case .hotel: return "bed.double"
        case .laundry: return "washer"
        case .library: return "books.vertical"
        case .museum: return "building.columns"
        case .nationalPark, .park: return "leaf"
        case .parking: return "p.square"
        case .pharmacy: return "pills"
        case .police: return "shield"
        case .postOffice: return "envelope"
        case .publicTransport: return "bus"
        case .restaurant: return "fork.knife"
        case .restroom: return "figure.stand"
        case .school, .university: return "graduationcap"
        case .stadium: return "sportscourt"
        case .store: return "bag"
        case .theater: return "theatermasks"
        case .zoo: return "tortoise"
        default: return "mappin"
        }
    }
}
