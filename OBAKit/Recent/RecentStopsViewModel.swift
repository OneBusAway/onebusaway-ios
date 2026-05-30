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
            // No current region (mid-region-change, first launch race, denied location).
            // The user sees a generic empty state — log so the condition is observable.
            Logger.warn("RecentStopsViewModel.loadData: currentRegion is nil; returning empty recent stops.")
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

    @discardableResult
    func delete(alarm: Alarm) -> Task<Void, Never> {
        application.userDataStore.delete(alarm: alarm)
        loadData()
        // Capture the service directly: if the VM is deallocated mid-delete (common when
        // the user pops the view right after tapping delete), [weak self] would abort
        // the DELETE before it ran, leaving the alarm live on the Obaco server.
        // The returned Task is `@discardableResult` for the call site, but tests can
        // await it to assert on remote-side behaviour.
        let service = application.obacoService
        let url = alarm.url
        return Task {
            do {
                try await service?.deleteAlarm(url: url)
            } catch {
                Logger.error("Failed to delete alarm remotely: \(error.localizedDescription)")
            }
        }
    }
}
