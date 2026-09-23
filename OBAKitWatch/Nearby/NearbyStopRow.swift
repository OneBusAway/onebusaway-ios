//
//  NearbyStopRow.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import CoreLocation
import MapKit
import OBAKitCore

struct NearbyStopRow: View {
    let stop: Stop
    let origin: CLLocation?
    let formatters: Formatters

    private var routeNames: [String] {
        (stop.routes ?? []).map(\.shortName)
    }

    private var distanceText: String? {
        guard let origin else { return nil }
        let meters = stop.location.distance(from: origin)
        return formatters.distanceFormatter.string(fromDistance: meters)
    }

    var body: some View {
        let names = routeNames
        return VStack(alignment: .leading, spacing: 2) {
            Text(stop.nameWithLocalizedDirectionAbbreviation)
                .font(.headline)
                .lineLimit(2)
            if !names.isEmpty {
                Text(names.formatted(.list(type: .and, width: .narrow)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let distanceText {
                Text(distanceText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
