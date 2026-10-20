//
//  HomeAlertsSectionModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// The home sheet's service alerts: the agencies' recent high-severity alerts,
/// which the UIKit map's nearby list shows above its stops.
///
/// Read from `AgencyAlertsStore`, which fetches on its own schedule.
@MainActor
final class HomeAlertsSectionModel: NSObject, ObservableObject, AgencyAlertsDelegate {

    @Published private(set) var alerts: [AgencyAlert] = []

    private let alertsStore: AgencyAlertsStore

    init(alertsStore: AgencyAlertsStore) {
        self.alertsStore = alertsStore
        super.init()
        alertsStore.addDelegate(self)
        reload()
    }

    isolated deinit {
        alertsStore.removeDelegate(self)
    }

    /// Guarded against a no-op write, as the other section models are.
    func reload() {
        let reloaded = alertsStore.recentHighSeverityAlerts
        guard reloaded.map(\.id) != alerts.map(\.id) else { return }
        alerts = reloaded
    }

    // MARK: - AgencyAlertsDelegate

    func agencyAlertsUpdated() {
        reload()
    }
}
