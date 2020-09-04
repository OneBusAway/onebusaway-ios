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
    func sectionData(from alerts: [ServiceAlert], collapsedState: ServiceAlertsSectionData.CollapsedState) -> ServiceAlertsSectionData
    func tableSection(stops: [Stop], tapped: @escaping ListRowActionHandler) -> TableSectionData
    func tableSection(stops: [Stop], tapped: @escaping ListRowActionHandler, deleted: ListRowActionHandler?) -> TableSectionData
}

extension SectionDataBuilders where Self: AppContext {
    /// Converts an array of `ServiceAlert`s into `ServiceAlertsSectionData`.
    /// - Parameters:
    ///     - alerts: The list of `ServiceAlert`s that will be converted into `ServiceAlertsSectionData` objects.
    ///     - collapsedState: Whether this section of Service Alerts is collapsed.
    /// - Returns: A `ServiceAlertsSectionData` view model, suitable for returning via `ListAdapterDataSource`'s `objects(for:)` method.
    func sectionData(from alerts: [ServiceAlert], collapsedState: ServiceAlertsSectionData.CollapsedState) -> ServiceAlertsSectionData {
        let uniqued = Set<ServiceAlert>(alerts)
        let sorted = uniqued.sorted { $0.createdAt > $1.createdAt }
        let data: [ServiceAlertData] = sorted.map { alert in
            let isUnread = application.userDataStore.isUnread(serviceAlert: alert)
            return ServiceAlertData(serviceAlert: alert, isUnread: isUnread)
        }

        return ServiceAlertsSectionData(serviceAlertData: data, collapsed: collapsedState)
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
