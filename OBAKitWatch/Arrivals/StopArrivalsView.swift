//
//  StopArrivalsView.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

struct StopArrivalsView: View {
    let model: StopArrivalsModel
    @Environment(WatchAppHost.self) private var host
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .navigationTitle(model.stop.nameWithLocalizedDirectionAbbreviation)
            .onAppear { model.startPolling() }
            .onDisappear { model.stopPolling() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.startPolling()
                } else {
                    model.stopPolling()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView(OBALoc("arrivals.loading", value: "Loading departures…", comment: "Progress text"))
        case .empty(let updatedAt):
            VStack(spacing: 8) {
                MessageView(
                    text: OBALoc("arrivals.empty", value: "No departures in the next 60 minutes.", comment: "Empty state"),
                    systemImage: "bus"
                )
                updatedAtText(updatedAt)
            }
        case .failed(let message):
            MessageView(
                text: message,
                systemImage: "exclamationmark.triangle",
                actionTitle: OBALoc("nearby.retry", value: "Retry", comment: "Button after a failure"),
                action: { model.retry() }
            )
        case .loaded(let arrivals, let updatedAt, let stale):
            List {
                Section {
                    ForEach(arrivals) { arrival in
                        ArrivalRow(arrival: arrival, formatters: host.formatters)
                    }
                } footer: {
                    updatedAtText(updatedAt)
                        .foregroundStyle(stale ? .orange : .secondary)
                }
            }
        }
    }

    private func updatedAtText(_ date: Date) -> Text {
        Text(String(
            format: OBALoc("arrivals.updated_at_fmt", value: "Updated at %@", comment: "%@ is a short time, e.g. 3:42 PM"),
            host.formatters.timeFormatter.string(from: date)
        ))
        .font(.caption2)
    }
}
