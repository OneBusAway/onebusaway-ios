//
//  NearbyRoutesView.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import CoreLocation
import OBAKitCore

struct NearbyRoutesView: View {
    let model: NearbyRoutesModel
    @Environment(WatchAppHost.self) private var host: WatchAppHost?
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    var body: some View {
        content
            .navigationTitle(OBALoc("nearby.title", value: "Nearby", comment: "Nearby screen title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.refresh()
                    } label: {
                        Label(Strings.refresh, systemImage: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                isVisible = true
                if scenePhase == .active {
                    model.startPolling()
                }
            }
            .onDisappear {
                isVisible = false
                model.stopPolling()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    if isVisible {
                        model.startPolling()
                    }
                } else {
                    model.stopPolling()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .awaitingAuthorization:
            MessageView(
                text: OBALoc("nearby.awaiting_authorization", value: "Allow location access to see stops near you.", comment: "Shown while the system location prompt is up"),
                systemImage: "location"
            )
        case .locationDenied:
            MessageView(
                text: OBALoc("nearby.location_denied", value: "Location access is off. Nearby stops need your location.", comment: "Shown when location is denied or restricted"),
                systemImage: "location.slash"
            )
        case .locating:
            ProgressView(OBALoc("nearby.locating", value: "Finding your location…", comment: "Progress text"))
        case .loading:
            ProgressView(OBALoc("nearby.loading", value: "Finding nearby routes…", comment: "Progress text while nearby stops' departures load"))
        case .noRegion:
            MessageView(
                text: OBALoc("nearby.no_region", value: "No transit region here.", comment: "The fix is outside every supported region"),
                systemImage: "map"
            )
        case .failed(let message):
            MessageView(
                text: message,
                systemImage: "exclamationmark.triangle",
                actionTitle: Strings.retry,
                action: { model.refresh() }
            )
        case .empty:
            MessageView(
                text: OBALoc("nearby.empty", value: "No departures nearby in the next hour.", comment: "No nearby stop has a departure in the next 60 minutes"),
                systemImage: "bus",
                actionTitle: Strings.retry,
                action: { model.refresh() }
            )
        case .loaded(let directions):
            List {
                Section {
                    ForEach(directions) { direction in
                        NavigationLink(value: direction.key) {
                            RouteDirectionCard(direction: direction)
                        }
                    }
                } footer: {
                    if let loadedAt = model.loadedAt {
                        VStack(alignment: .leading, spacing: 2) {
                            updatedAtText(loadedAt)
                            if model.isStale {
                                Text(OBALoc("nearby.stale", value: "This data may be out of date.", comment: "Shown when nearby routes could not be refreshed"))
                                    .font(.caption2)
                            }
                        }
                        .foregroundStyle(model.isStale ? .orange : .secondary)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func updatedAtText(_ date: Date) -> Text {
        let timeString: String
        if let host {
            timeString = host.formatters.timeFormatter.string(from: date)
        } else {
            timeString = date.formatted(date: .omitted, time: .shortened)
        }
        return Text(String(
            format: OBALoc("arrivals.updated_at_fmt", value: "Updated at %@", comment: "%@ is a short time, e.g. 3:42 PM"),
            timeString
        ))
        .font(.caption2)
    }
}

#Preview("Awaiting authorization") {
    NavigationStack { NearbyRoutesView(model: NearbyRoutesModel(phase: .awaitingAuthorization)) }
}

#Preview("Denied") {
    NavigationStack { NearbyRoutesView(model: NearbyRoutesModel(phase: .locationDenied)) }
}

#Preview("Locating") {
    NavigationStack { NearbyRoutesView(model: NearbyRoutesModel(phase: .locating)) }
}

#Preview("Loading") {
    NavigationStack { NearbyRoutesView(model: NearbyRoutesModel(phase: .loading)) }
}

#Preview("No region") {
    NavigationStack { NearbyRoutesView(model: NearbyRoutesModel(phase: .noRegion)) }
}

#Preview("Failed") {
    NavigationStack { NearbyRoutesView(model: NearbyRoutesModel(phase: .failed("The request timed out."))) }
}

#Preview("Empty") {
    NavigationStack { NearbyRoutesView(model: NearbyRoutesModel(phase: .empty)) }
}

#Preview("Stale") {
    NavigationStack {
        NearbyRoutesView(model: NearbyRoutesModel(
            phase: .loaded([
                .previewDirection(shortName: "44", headsign: "UW Stadium"),
                .previewDirection(shortName: "48", headsign: "Mt Baker")
            ]),
            isStale: true
        ))
    }
}

private extension NearbyRouteDirection {
    static func previewDirection(shortName: String, headsign: String) -> NearbyRouteDirection {
        let routeData = Data("{\"id\":\"preview_\(shortName)\",\"shortName\":\"\(shortName)\",\"agencyId\":\"1\",\"type\":3}".utf8)
        guard let route = try? JSONDecoder().decode(Route.self, from: routeData) else {
            fatalError("Invalid preview route JSON")
        }
        let stop = Stop(id: "stop_\(shortName)", name: "15th Ave NE & NE 45th St")
        let stopDirection = RouteDirectionStop(stop: stop, distance: 120, departures: [])
        return NearbyRouteDirection(
            key: RouteDirectionKey(routeID: route.id, direction: "0"),
            route: route,
            headsign: headsign,
            stops: [stopDirection]
        )
    }
}
