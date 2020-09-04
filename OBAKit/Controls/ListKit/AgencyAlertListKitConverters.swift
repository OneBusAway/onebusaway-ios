//
//  AgencyAlertListKitConverters.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore
import SafariServices

/// Describes methods capable of converting REST API models into view
/// models suitable for display in an IGListKit collection controller.
///
/// - Note: The data produced by methods in this protocol are specifically
///         designed to work with `objects(for listAdapter:)`.
protocol AgencyAlertListKitConverters {
    var application: Application { get }
    func tableSections(agencyAlerts: [AgencyAlert], collapsedSections: [String]) -> [AgencyAlertsSectionData]
    func presentAlert(_ alert: AgencyAlert)
}

extension AgencyAlertListKitConverters where Self: UIViewController {

    /// Converts an array of `AgencyAlert`s into `[AgencyAlertsSectionData]` objects, which can be displayed by IGListKit.
    ///
    /// - Note: The data produced by this method is specifically designed to work with `objects(for listAdapter:)`.
    ///
    /// - Parameters:
    ///   - agencyAlerts: An array of `AgencyAlert`s.
    ///   - collapsedSections: An array of Strings indicating which section (based on the section title) should be collapsed.
    /// - Returns: A sorted array of `AgencyAlertsSectionData` object representing the array of `AgencyAlert`s for use with IGListKit.
    func tableSections(agencyAlerts: [AgencyAlert], collapsedSections: [String]) -> [AgencyAlertsSectionData] {
        let groupedAlerts = Dictionary(grouping: agencyAlerts, by: { $0.agency?.agency.name ?? "" })
        return groupedAlerts.map { group -> AgencyAlertsSectionData in
            let alerts = group.value.map { AgencyAlertData(agencyAlert: $0, isUnread: false) }
            let isCollapsed = collapsedSections.contains(group.key)
            return AgencyAlertsSectionData(agencyName: group.key, alerts: alerts, isCollapsed: isCollapsed)   // TODO: fix iscollapsed
        }.sorted(by: \.agencyName)
    }

    func presentAlert(_ alert: AgencyAlert) {
        if let url = alert.URLForLocale(application.locale) {
            let safari = SFSafariViewController(url: url)
            application.viewRouter.present(safari, from: self, isModal: true)
        } else {
            let title = alert.titleForLocale(application.locale)
            let body = alert.bodyForLocale(application.locale)
            AlertPresenter.showDismissableAlert(title: title, message: body, presentingController: self)
        }
    }

    // MARK: - Locale

    private var languageCode: String {
        application.locale.languageCode ?? "en"
    }
}
