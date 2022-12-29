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
    func listSections(agencyAlerts: [AgencyAlert]) -> [OBAListViewSection]
    func listSection(serviceAlerts: [ServiceAlert], showSectionTitle: Bool, sectionID: String) -> OBAListViewSection
    func presentAlert(_ alert: TransitAlertDataListViewModel)
}

extension AgencyAlertListViewConverters where Self: UIViewController {
    /// Converts an array of `AgencyAlert`s into `[OBAListViewSection]`, sorted by agency, which can be displayed by OBAListView.
    ///
    /// - Parameter agencyAlerts: An array of `AgencyAlert`s.
    /// - Returns: A sorted array of `[OBAListViewSection]` representing the array of `AgencyAlert`s for use with OBAListView.  The sections provided will have a `agency_alert` prefix for its section ID.
    func listSections(agencyAlerts: [AgencyAlert]) -> [OBAListViewSection] {
        let groupedAlerts = Dictionary(grouping: agencyAlerts, by: { $0.agency?.agency.name ?? "" })
        return groupedAlerts.map { group -> OBAListViewSection in
            let presentAlertAction: OBAListViewAction<TransitAlertDataListViewModel> = { [weak self] item in self?.presentAlert(item) }
            let viewModels: [TransitAlertDataListViewModel] = group.value.map { alert -> TransitAlertDataListViewModel in
                let isUnread = application.alertsStore.isAlertUnread(alert)
                return TransitAlertDataListViewModel(alert, isUnread: isUnread, forLocale: Locale.current, onSelectAction: presentAlertAction)
            }

            let alerts = viewModels.sorted(by: \.title) // remove duplicates
            return OBAListViewSection(id: "agency_alerts_\(group.key)", title: group.key, contents: alerts)
        }.sorted(by: \.id)
    }

    /// Converts an array of `ServiceAlert`s into `OBAListViewSection`,  which can be displayed by OBAListView.
    ///
    /// - Parameters:
    ///     - serviceAlerts: An array of `ServiceAlert`s.
    ///     - showSectionTitle: Whether to display a section header and localized title.
    ///     - sectionID: The section ID to use with `OBAListViewSection`. The default value is `service_alerts`.
    /// - Returns: An `OBAListViewSection` representing the array of `ServiceAlert`s for use with OBAListView.
    func listSection(serviceAlerts: [ServiceAlert], showSectionTitle: Bool, sectionID: String = "service_alerts") -> OBAListViewSection {
        let onSelectAction: OBAListViewAction<TransitAlertDataListViewModel> = { [weak self] item in self?.presentAlert(item) }
        let items = serviceAlerts.map { TransitAlertDataListViewModel($0, isUnread: false, forLocale: .current, onSelectAction: onSelectAction) }
        let title: String?
        if showSectionTitle {
            if items.count > 1 {
                title = "\(Strings.serviceAlerts) (\(items.count))"
            } else {
                title = Strings.serviceAlert
            }
        } else {
            title = nil
        }
        return OBAListViewSection(id: sectionID, title: title, contents: items)
    }

    func presentAlert(_ alert: TransitAlertDataListViewModel) {
        application.viewRouter.navigateTo(alert: alert.transitAlert, from: self)
    }
}
