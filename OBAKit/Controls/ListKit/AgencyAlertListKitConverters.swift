//
//  AgencyAlertListKitConverters.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 12/28/19.
//

import UIKit
import OBAKitCore
import SafariServices

/// Describes methods capable of converting REST API models into view
/// models suitable for display in an IGListKit collection controller.
///
/// - Note: The data produced by methods in this protocol are specifically
///         designed to work with `objects(for listAdapter:)`.
public protocol AgencyAlertListKitConverters {
    var application: Application { get }
    func tableSections(agencyAlerts: [AgencyAlert], tapped: @escaping ListRowActionHandler) -> [MessageSectionData]
    func presentAlert(_ alert: AgencyAlert)
}

public extension AgencyAlertListKitConverters where Self: UIViewController {

    /// Converts an array of `AgencyAlert`s into `[MessageSectionData]` objects, which can be displayed by IGListKit.
    ///
    /// - Note: The data produced by this method is specifically designed to work with `objects(for listAdapter:)`.
    ///
    /// - Parameters:
    ///   - agencyAlerts: An array of `AgencyAlert`s.
    ///   - tapped: A tap handler, invoked when any of the `AgencyAlert`s are tapped.
    /// - Returns: A `TableSectionData` object representing the array of `AgencyAlert`s.
    func tableSections(agencyAlerts: [AgencyAlert], tapped: @escaping ListRowActionHandler) -> [MessageSectionData] {
        return agencyAlerts.compactMap { (agencyAlert: AgencyAlert) -> MessageSectionData? in
            guard let row = buildTableRowData(agencyAlert: agencyAlert, tapped: tapped) else {
                return nil
            }
            return row
        }
    }

    func presentAlert(_ alert: AgencyAlert) {
        if let url = alert.URLForLocale(application.locale) {
            let safari = SFSafariViewController(url: url)
            application.viewRouter.present(safari, from: self, isModalInPresentation: true)
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

        let rowData = MessageSectionData(author: agencyAlert.agency?.agency.name, date: formattedDateTime, subject: title, summary: agencyAlert.bodyForLocale(application.locale), tapped: tapped)

        rowData.object = agencyAlert

        return rowData
    }
}
