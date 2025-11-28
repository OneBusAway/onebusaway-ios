//
//  StopsListView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// A list view displaying stops, typically shown in the FloatingPanel default state
struct StopsListView: View {
    let stops: [Stop]
    let onStopSelected: (Stop) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Nearby Stops")
                    .font(.headline)
                Spacer()
                Text("\(stops.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Stop list
            if stops.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(stops) { stop in
                            StopRowView(stop: stop) {
                                onStopSelected(stop)
                            }
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mappin.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No stops in this area")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Zoom in to see nearby stops")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }
}

/// A row displaying a single stop with transport icon and name
struct StopRowView: View {
    let stop: Stop
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Transport icon based on route type
                Image(systemName: iconName(for: stop.prioritizedRouteTypeForDisplay))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)

                // Stop name with direction (e.g., "15th Ave E & E Galer St (W)")
                Text(stop.nameWithLocalizedDirectionAbbreviation)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

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

    private func iconName(for routeType: Route.RouteType) -> String {
        switch routeType {
        case .lightRail: return "tram.fill"
        case .subway: return "tram.fill.tunnel"
        case .rail: return "train.side.front.car"
        case .ferry: return "ferry.fill"
        case .cableCar, .gondola: return "cablecar.fill"
        default: return "bus.fill"
        }
    }
}
