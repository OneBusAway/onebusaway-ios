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
        let rows = stops.map { TableRowData(stop: $0, tapped: tapped) }
        return TableSectionData(title: nil, rows: rows)
    }
}

public extension TableRowData {
    convenience init(stop: Stop, tapped: ListRowTapHandler?) {
        let title = Formatters.formattedTitle(stop: stop)
        let subtitle = Formatters.formattedRoutes(stop.routes)
        
        self.init(title: title, attributedTitle: nil, subtitle: subtitle, style: .subtitle, accessoryType: .disclosureIndicator, tapped: tapped)
                  
        self.object = stop
    }
}
