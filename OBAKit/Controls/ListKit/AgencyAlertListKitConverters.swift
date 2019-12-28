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
    func tableSection(agencyAlerts: [AgencyAlert], tapped: @escaping ListRowActionHandler) -> TableSectionData
    func tableSection(agencyAlerts: [AgencyAlert], tapped: @escaping ListRowActionHandler, deleted: ListRowActionHandler?) -> TableSectionData
    func presentAlert(_ alert: AgencyAlert)
}

public extension AgencyAlertListKitConverters where Self: UIViewController {

    /// Converts an array of `AgencyAlert`s into a `TableSectionData` object, which can be displayed by IGListKit.
    ///
    /// - Note: The data produced by this method is specifically designed to work with `objects(for listAdapter:)`.
    ///
    /// - Parameters:
    ///   - agencyAlerts: An array of `AgencyAlert`s.
    ///   - tapped: A tap handler, invoked when any of the `AgencyAlert`s are tapped.
    /// - Returns: A `TableSectionData` object representing the array of `AgencyAlert`s.
    func tableSection(agencyAlerts: [AgencyAlert], tapped: @escaping ListRowActionHandler) -> TableSectionData {
        let rows = agencyAlerts.compactMap { (agencyAlert: AgencyAlert) -> TableRowData? in
            guard let row = buildTableRowData(agencyAlert: agencyAlert, tapped: tapped) else {
                return nil
            }
            return row
        }
        return TableSectionData(title: nil, rows: rows)
    }

    /// Converts an array of `AgencyAlert`s into a `TableSectionData` object, which can be displayed by IGListKit.
    ///
    /// - Note: The data produced by this method is specifically designed to work with `objects(for listAdapter:)`.
    ///
    /// - Parameters:
    ///   - agencyAlerts: An array of `AgencyAlert`s.
    ///   - tapped: A tap handler, invoked when any of the `AgencyAlert`s are tapped.
    ///   - deleted: Optional handler called when swipe-to-delete is invoked on a row.
    /// - Returns: A `TableSectionData` object representing the array of `AgencyAlert`s.
    func tableSection(
        agencyAlerts: [AgencyAlert],
        tapped: @escaping ListRowActionHandler,
        deleted: ListRowActionHandler? = nil
    ) -> TableSectionData {
        let rows = agencyAlerts.compactMap { (agencyAlert: AgencyAlert) -> TableRowData? in
            guard let row = buildTableRowData(agencyAlert: agencyAlert, tapped: tapped) else {
                return nil
            }
            row.deleted = deleted
            return row
        }
        return TableSectionData(title: nil, rows: rows)
    }

    func presentAlert(_ alert: AgencyAlert) {
        if let url = localizedAlertURL(alert) {
            let safari = SFSafariViewController(url: url)
            application.viewRouter.present(safari, from: self, isModalInPresentation: true)
        }
        else {
            let title = localizedAlertTitle(alert)
            let body = localizedAlertBody(alert)
            AlertPresenter.showDismissableAlert(title: title, message: body, presentingController: self)
        }
    }

    // MARK: - Locale

    private var languageCode: String {
        application.locale.languageCode ?? defaultLanguageCode()
    }

    private func defaultLanguageCode() -> String { "en" }

    private func localizedAlertTitle(_ alert: AgencyAlert) -> String? {
        let language = languageCode
        return alert.title(language: language) ?? alert.title(language: defaultLanguageCode())
    }

    private func localizedAlertBody(_ alert: AgencyAlert) -> String? {
        let language = languageCode
        return alert.body(language: language) ?? alert.body(language: defaultLanguageCode())
    }

    private func localizedAlertURL(_ alert: AgencyAlert) -> URL? {
        let language = languageCode
        return alert.url(language: language) ?? alert.url(language: defaultLanguageCode())
    }

    // MARK: - TableRowData

    private func buildTableRowData(agencyAlert: AgencyAlert, tapped: ListRowActionHandler?) -> TableRowData? {
        guard let title = localizedAlertTitle(agencyAlert) else { return nil }

        let formattedDateTime: String?
        if let startDate = agencyAlert.startDate {
            formattedDateTime = application.formatters.contextualDateTimeString(startDate)
        }
        else {
            formattedDateTime = nil
        }

        let rowData = TableRowData(title: title, subtitle: formattedDateTime ?? "", accessoryType: .disclosureIndicator, tapped: tapped)
        rowData.object = agencyAlert

        return rowData
    }
}
