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
    func tableSections(agencyAlerts: [AgencyAlert], tapped: @escaping ListRowActionHandler) -> [AgencyAlertsSectionData]
    func presentAlert(_ alert: AgencyAlert)
}

extension AgencyAlertListKitConverters where Self: UIViewController {

    /// Converts an array of `AgencyAlert`s into `[MessageSectionData]` objects, which can be displayed by IGListKit.
    ///
    /// - Note: The data produced by this method is specifically designed to work with `objects(for listAdapter:)`.
    ///
    /// - Parameters:
    ///   - agencyAlerts: An array of `AgencyAlert`s.
    ///   - tapped: A tap handler, invoked when any of the `AgencyAlert`s are tapped.
    /// - Returns: A `TableSectionData` object representing the array of `AgencyAlert`s.
    func tableSections(agencyAlerts: [AgencyAlert], tapped: @escaping ListRowActionHandler) -> [AgencyAlertsSectionData] {
        let groupedAlerts = Dictionary(grouping: agencyAlerts, by: { $0.agency?.agency.name ?? "" })
        return groupedAlerts.map { group -> AgencyAlertsSectionData in
            let alerts = group.value.map { AgencyAlertData(agencyAlert: $0, isUnread: false) }
            return AgencyAlertsSectionData(agencyName: group.key, alerts: alerts, isCollapsed: false)   // TODO: fix iscollapsed
        }
//        return agencyAlerts.compactMap { (agencyAlert: AgencyAlert) -> MessageSectionData? in
//            guard let row = buildTableRowData(agencyAlert: agencyAlert, tapped: tapped) else {
//                return nil
//            }
//            return row
//        }
    }

    func presentAlert(_ alert: AgencyAlert) {
        if let url = alert.URLForLocale(application.locale) {
            let safari = SFSafariViewController(url: url)
            application.viewRouter.present(safari, from: self, isModal: true)
        }
        else {
            let title = alert.titleForLocale(application.locale)
            let body = alert.bodyForLocale(application.locale)
            AlertPresenter.showDismissableAlert(title: title, message: body, presentingController: self)
        }
    }

    // MARK: - Locale

    private var languageCode: String {
        application.locale.languageCode ?? "en"
    }

    // MARK: - TableRowData

    private func buildTableRowData(agencyAlert: AgencyAlert, tapped: ListRowActionHandler?) -> MessageSectionData? {
        guard let title = agencyAlert.titleForLocale(application.locale) else { return nil }

        let formattedDateTime: String?
        if let startDate = agencyAlert.startDate {
            formattedDateTime = application.formatters.contextualDateTimeString(startDate)
        }
        else {
            formattedDateTime = nil
        }

        let rowData = MessageSectionData(
            author: agencyAlert.agency?.agency.name,
            date: formattedDateTime,
            subject: title,
            summary: agencyAlert.bodyForLocale(application.locale),
            isUnread: false,
            tapped: tapped
        )

        rowData.object = agencyAlert

        return rowData
    }
}
