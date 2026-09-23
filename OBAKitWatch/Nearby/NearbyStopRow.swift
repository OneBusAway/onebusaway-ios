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
import OBAKitCore

struct NearbyStopRow: View {
    let stop: Stop
    let origin: CLLocation?

    private var routeNames: [String] {
        (stop.routes ?? []).map(\.shortName)
    }

    private var distanceText: String? {
        guard let origin else { return nil }
        let meters = stop.location.distance(from: origin)
        return Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stop.nameWithLocalizedDirectionAbbreviation)
                .font(.headline)
                .lineLimit(2)
            if !routeNames.isEmpty {
                Text(routeNames.formatted(.list(type: .and, width: .narrow)))
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
