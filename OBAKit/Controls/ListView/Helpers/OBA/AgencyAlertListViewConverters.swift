//
//  AgencyAlertListViewConverters.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore
import SafariServices

/// Describes methods capable of converting REST API models into `OBAListView` view models.
protocol AgencyAlertListViewConverters {
    var application: Application { get }
    func tableSections(agencyAlerts: [AgencyAlert]) -> [OBAListViewSection]
    func presentAlert(_ alert: TransitAlertDataListViewModel)
}

extension AgencyAlertListViewConverters where Self: UIViewController {
    /// Converts an array of `AgencyAlert`s into `[OBAListViewSection]`, sorted by agency, which can be displayed by OBAListView.
    ///
    /// - Parameters:
    ///   - agencyAlerts: An array of `AgencyAlert`s.
    /// - Returns: A sorted array of `[OBAListViewSection]` representing the array of `AgencyAlert`s for use with OBAListView.  The sections provided will have a `agency_alert` prefix for its section ID.
    func tableSections(agencyAlerts: [AgencyAlert]) -> [OBAListViewSection] {
        let groupedAlerts = Dictionary(grouping: agencyAlerts, by: { $0.agency?.agency.name ?? "" })
        return groupedAlerts.map { group -> OBAListViewSection in
            let viewModels: [TransitAlertDataListViewModel] = group.value.map { alert -> TransitAlertDataListViewModel in
                return TransitAlertDataListViewModel(alert, isUnread: false, forLocale: Locale.current, onSelectAction: presentAlert)
            }

            let alerts = Set(viewModels).allObjects.sorted(by: \.title) // remove duplicates
            return OBAListViewSection(id: "agency_alerts_\(group.key)", title: group.key, contents: alerts)
        }.sorted(by: \.id)
    }

    func presentAlert(_ alert: TransitAlertDataListViewModel) {
        application.viewRouter.navigateTo(alert: alert.transitAlert, from: self)
    }
}
