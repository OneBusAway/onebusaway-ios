//
//  AgencyAlertsViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Combine
import OBAKitCore

/// Shared ViewModel for `AgencyAlertsViewController`.
///
/// Owns the deduplicated `[AgencyAlert]` list, loading state, and the
/// collapsed-section set. Adopts `AgencyAlertsDelegate` directly so the VC
/// no longer needs to bridge store updates.
@MainActor
final class AgencyAlertsViewModel: NSObject, ObservableObject, AgencyAlertsDelegate {

    // MARK: - Published State

    /// Deduplicated alerts (by `id`), in the order returned by the store.
    @Published private(set) var alerts: [AgencyAlert] = []

    /// `true` while a refresh is in flight; flips to `false` on the next
    /// `agencyAlertsUpdated()` callback.
    @Published private(set) var isLoading: Bool = false

    /// IDs of collapsed sections; round-tripped by the VC's collapsible-sections delegate.
    /// Not `@Published` — no observer in the VC, the VC reads/writes through directly.
    var collapsedSections: Set<String> = []

    // MARK: - Private

    private let application: Application
    private let alertsStore: AgencyAlertsStore

    // MARK: - Init

    init(application: Application) {
        self.application = application
        self.alertsStore = application.alertsStore
        super.init()
        self.alertsStore.addDelegate(self)
        self.alerts = dedupedAlerts()
    }

    // MARK: - Intent

    func reloadServerData() {
        isLoading = true
        alertsStore.checkForUpdates()
    }

    /// Returns the items to feed into a `UIActivityViewController` when sharing
    /// the given alert. Returns `[url]` when the alert has a localized URL,
    /// otherwise `[title, body]`.
    func shareActivityItems(for alert: TransitAlertDataListViewModel) -> [Any] {
        if let url = alert.localizedURL {
            return [url]
        }
        return [alert.title, alert.body]
    }

    // MARK: - AgencyAlertsDelegate

    func agencyAlertsUpdated() {
        alerts = dedupedAlerts()
        isLoading = false
    }

    func agencyAlertsStore(_ store: AgencyAlertsStore, displayError error: Error) {
        isLoading = false
    }

    // MARK: - Helpers

    private func dedupedAlerts() -> [AgencyAlert] {
        var seenIDs = Set<String>()
        return alertsStore.agencyAlerts.filter { seenIDs.insert($0.id).inserted }
    }
}
