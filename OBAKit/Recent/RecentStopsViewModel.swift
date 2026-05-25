//
//  RecentStopsViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

@MainActor
final class RecentStopsViewModel: ObservableObject {

    @Published private(set) var alarms: [Alarm] = []
    @Published private(set) var recentStops: [Stop] = []

    private let application: Application

    init(application: Application) {
        self.application = application
    }

    func loadData() {
        application.userDataStore.deleteExpiredAlarms()
        alarms = application.userDataStore.alarms
        guard let currentRegion = application.currentRegion else {
            recentStops = []
            return
        }
        recentStops = application.userDataStore.recentStops.filter {
            $0.regionIdentifier == currentRegion.regionIdentifier
        }
    }

    func deleteAllRecentStops() {
        application.userDataStore.deleteAllRecentStops()
        recentStops = []
    }

    func delete(recentStop: Stop) {
        application.userDataStore.delete(recentStop: recentStop)
        loadData()
    }

    func delete(alarm: Alarm) {
        application.userDataStore.delete(alarm: alarm)
        loadData()
        // The alarm is already gone locally; a remote-delete failure isn't actionable by
        // the user, so log it rather than surfacing a modal error for a background op.
        Task { [weak self] in
            guard let self else { return }
            do {
                try await application.obacoService?.deleteAlarm(url: alarm.url)
            } catch {
                Logger.error("Failed to delete alarm remotely: \(error.localizedDescription)")
            }
        }
    }
}
