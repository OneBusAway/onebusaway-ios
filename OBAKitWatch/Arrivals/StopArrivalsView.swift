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
    @State private var isVisible = false

    var body: some View {
        content
            .navigationTitle(model.stop.nameWithLocalizedDirectionAbbreviation)
            .onAppear {
                isVisible = true
                model.startPolling()
            }
            .onDisappear {
                isVisible = false
                model.stopPolling()
            }
            .onChange(of: scenePhase) { _, phase in
                // Forward the phase so the poller pauses in the background and
                // resumes with an immediate fetch on foregrounding, instead of
                // cancelling and restarting the poll. A wrist raise makes every
                // view in the stack active again, including this one when a
                // pushed screen is covering it. Only the one on screen should
                // poll, so a covered screen still never starts polling.
                model.setScenePhase(PollerScenePhase(phase))
                if phase == .active, isVisible {
                    model.startPolling()
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
                    systemImage: "bus",
                    actionTitle: Strings.retry,
                    action: { model.retry() }
                )
                updatedAtText(updatedAt)
            }
        case .offline:
            MessageView(
                text: Strings.offlineTitle,
                secondaryText: Strings.offlineSummary,
                systemImage: "wifi.slash",
                actionTitle: Strings.retry,
                action: { model.retry() }
            )
        case .failed(let message):
            MessageView(
                text: message,
                systemImage: "exclamationmark.triangle",
                actionTitle: Strings.retry,
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

extension PollerScenePhase {
    /// Maps SwiftUI's scene phase onto the poller's own phase, which has the
    /// same three cases.
    init(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active: self = .active
        case .inactive: self = .inactive
        case .background: self = .background
        @unknown default: self = .inactive
        }
    }
}
