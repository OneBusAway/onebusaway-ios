//
//  ModelViewModelConverters.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/26/19.
//

import UIKit

/// Describes methods capable of converting REST API models into view
/// models suitable for display in an IGListKit collection controller.
///
/// - Note: The data produced by methods in this protocol are specifically
///         designed to work with `objects(for listAdapter:)`.
public protocol ModelViewModelConverters {
    func tableSection(from stops: [Stop], tapped: @escaping ListRowTapHandler) -> TableSectionData
}

public extension ModelViewModelConverters where Self: UIViewController {

    /// Converts an array of `Stop`s into a `TableSectionData` object, which can be displayed by IGListKit.
    ///
    /// - Note: The data produced by this method is specifically designed to work with `objects(for listAdapter:)`.
    ///
    /// - Parameters:
    ///   - stops: An array of `Stop`s.
    ///   - tapped: A tap handler, invoked when any of the `Stop`s are tapped.
    /// - Returns: A `TableSectionData` object representing the array of `Stop`s.
    func tableSection(from stops: [Stop], tapped: @escaping ListRowTapHandler) -> TableSectionData {
        let rows = stops.map { s -> TableRowData in
            let routeNames = s.routes.map { $0.shortName }.joined(separator: ", ")
            let data = TableRowData(title: s.name, subtitle: routeNames, accessoryType: .disclosureIndicator, tapped: tapped)
            data.object = s
            return data
        }

        return TableSectionData(title: nil, rows: rows)
    }
}
