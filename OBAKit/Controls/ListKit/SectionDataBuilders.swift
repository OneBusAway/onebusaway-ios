//
//  SectionDataBuilders.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore
import IGListKit

/// Describes methods capable of converting REST API models into view
/// models suitable for display in an IGListKit collection controller.
///
/// - Note: The data produced by methods in this protocol are specifically
///         designed to work with `objects(for listAdapter:)`.
protocol SectionDataBuilders: NSObjectProtocol {
    func sectionData(from alerts: [ServiceAlert]) -> [MessageSectionData]
    func tableSection(stops: [Stop], tapped: @escaping ListRowActionHandler) -> TableSectionData
    func tableSection(stops: [Stop], tapped: @escaping ListRowActionHandler, deleted: ListRowActionHandler?) -> TableSectionData
}

extension SectionDataBuilders where Self: AppContext {

    /// Converts an array of `Situation`s into `MessageSectionData` objects, which look like rows in Mail.app.
    /// - Parameter alerts: The list of `Situation`s that will be converted into `MessageSectionData` objects.
    /// - Returns: An array of `MessageSectionData` view models, suitable for returning via `ListAdapterDataSource`'s `objects(for:)` method.
    func sectionData(from alerts: [ServiceAlert]) -> [MessageSectionData] {
        var sections = [MessageSectionData]()
        for serviceAlert in Set(alerts).allObjects.sorted(by: { $0.createdAt > $1.createdAt }) {
            let formattedDate = application.formatters.shortDateTimeFormatter.string(from: serviceAlert.createdAt)
            let isUnread = application.userDataStore.isUnread(serviceAlert: serviceAlert)
            let message = MessageSectionData(author: Strings.serviceAlert,
                                             date: formattedDate,
                                             subject: serviceAlert.summary.value,
                                             summary: serviceAlert.situationDescription?.value,
                                             isUnread: isUnread) { [weak self] _ in
                guard let self = self else { return }
                let serviceAlertController = ServiceAlertViewController(serviceAlert: serviceAlert, application: self.application)
                self.application.viewRouter.navigate(to: serviceAlertController, from: self)
            }
            sections.append(message)
        }
        return sections
    }

    func sectionData(from alerts: [ServiceAlert], isCollapsed: Bool) -> ServiceAlertsSectionData {
        let uniqued = Set<ServiceAlert>(alerts)
        let sorted = uniqued.sorted { $0.createdAt > $1.createdAt }
        let data: [ServiceAlertData] = sorted.map { alert in
            let agencies = Set<String>(alert.affectedAgencies.map { $0.name }).joined(separator: ", ")
            let isUnread = application.userDataStore.isUnread(serviceAlert: alert)
            return ServiceAlertData(serviceAlert: alert, id: alert.id, title: alert.summary.value, agency: agencies, isUnread: isUnread)
        }

        return ServiceAlertsSectionData(serviceAlertData: data, isCollapsed: isCollapsed)
    }

    /// Converts an array of `Stop`s into a `TableSectionData` object, which can be displayed by IGListKit.
    ///
    /// - Note: The data produced by this method is specifically designed to work with `objects(for listAdapter:)`.
    ///
    /// - Parameters:
    ///   - stops: An array of `Stop`s.
    ///   - tapped: A tap handler, invoked when any of the `Stop`s are tapped.
    /// - Returns: A `TableSectionData` object representing the array of `Stop`s.
    func tableSection(stops: [Stop], tapped: @escaping ListRowActionHandler) -> TableSectionData {
        return tableSection(stops: stops, tapped: tapped, deleted: nil)
    }

    /// Converts an array of `Stop`s into a `TableSectionData` object, which can be displayed by IGListKit.
    ///
    /// - Note: The data produced by this method is specifically designed to work with `objects(for listAdapter:)`.
    ///
    /// - Parameters:
    ///   - stops: An array of `Stop`s.
    ///   - tapped: A tap handler, invoked when any of the `Stop`s are tapped.
    ///   - deleted: Optional handler called when swipe-to-delete is invoked on a row.
    /// - Returns: A `TableSectionData` object representing the array of `Stop`s.
    func tableSection(stops: [Stop], tapped: @escaping ListRowActionHandler, deleted: ListRowActionHandler? = nil) -> TableSectionData {
        let rows = stops.map { (stop: Stop) -> TableRowData in
            let row = TableRowData(stop: stop, tapped: tapped)
            row.deleted = deleted
            row.previewDestination = {
                StopViewController(application: self.application, stop: stop)
            }

            return row
        }
        return TableSectionData(rows: rows)
    }
}

extension TableRowData {

    /// Creates a row from a `Stop`. Includes a tap handler closure for easily assigning an action to the row.
    /// - Parameters:
    ///   - stop: The `Stop` used to create the row.
    ///   - tapped: The tap action handler.
    convenience init(stop: Stop, tapped: ListRowActionHandler?) {
        let title = Formatters.formattedTitle(stop: stop)
        let subtitle = Formatters.formattedRoutes(stop.routes)

        self.init(title: title, attributedTitle: nil, subtitle: subtitle, style: .subtitle, accessoryType: .disclosureIndicator, tapped: tapped)

        self.object = stop
    }
}
