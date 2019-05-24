//
//  TableData.swift
//  OBANext
//
//  Created by Aaron Brethorst on 1/15/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import Foundation
import IGListKit

typealias TableRowTapHandler = ((TableRowData) -> Void)

/// Models a single table row
class TableRowData: NSObject {

    let title: String?
    let attributedTitle: NSAttributedString?

    let subtitle: String?
    let accessoryType: UITableViewCell.AccessoryType
    let style: UITableViewCell.CellStyle

    let tapped: TableRowTapHandler?

    /// Default Initializer. Lets you set everything.
    ///
    /// - Parameters:
    ///   - title: The title of the row. Optional.
    ///   - attributedTitle: The attributed title of the row. Optional.
    ///   - subtitle: The subtitle of the row. Optional.
    ///   - style: The style (appearance/layout) of the row.
    ///   - accessoryType: The accessory type on the right side, if any.
    ///   - tapped: Tap handler.
    public init(title: String?, attributedTitle: NSAttributedString?, subtitle: String?, style: UITableViewCell.CellStyle, accessoryType: UITableViewCell.AccessoryType, tapped: TableRowTapHandler?) {
        self.title = title
        self.attributedTitle = attributedTitle
        self.subtitle = subtitle
        self.style = style
        self.accessoryType = accessoryType
        self.tapped = tapped

        super.init()
    }

    /// Create a default-style row with an attributed string title.
    ///
    /// - Parameters:
    ///   - attributedTitle: The attributed string title.
    ///   - accessoryType: The accessory type on the right side, if any.
    ///   - tapped: Tap handler.
    convenience init(attributedTitle: NSAttributedString, accessoryType: UITableViewCell.AccessoryType, tapped: TableRowTapHandler?) {
        self.init(title: nil, attributedTitle: attributedTitle, subtitle: nil, style: .default, accessoryType: accessoryType, tapped: tapped)
    }

    /// Create a default-style row with an accessory.
    ///
    /// - Parameters:
    ///   - title: The title for the row.
    ///   - accessoryType: The accessory type of the row.
    ///   - tapped: Tap handler
    convenience init(title: String, accessoryType: UITableViewCell.AccessoryType, tapped: TableRowTapHandler?) {
        self.init(title: title, attributedTitle: nil, subtitle: nil, style: .default, accessoryType: accessoryType, tapped: tapped)
    }

    /// Create a subtitle-style row with an accessory.
    ///
    /// - Parameters:
    ///   - title: The title for the row.
    ///   - subtitle: The subtitle for the row.
    ///   - accessoryType: The accessory type.
    ///   - tapped: Tap handler.
    convenience init(title: String, subtitle: String, accessoryType: UITableViewCell.AccessoryType, tapped: TableRowTapHandler?) {
        self.init(title: title, attributedTitle: nil, subtitle: subtitle, style: .subtitle, accessoryType: accessoryType, tapped: tapped)
    }

    /// Create a value-style row with an accessory.
    ///
    /// - Parameters:
    ///   - title: The title for the row.
    ///   - values: The value for the row.
    ///   - accessoryType: The accessory type.
    ///   - tapped: Tap handler.
    convenience init(title: String, value: String, accessoryType: UITableViewCell.AccessoryType, tapped: TableRowTapHandler?) {
        self.init(title: title, attributedTitle: nil, subtitle: value, style: .value1, accessoryType: accessoryType, tapped: tapped)
    }

    override var debugDescription: String {
        let desc = super.debugDescription
        let props: [String: Any] = ["title": title as Any, "subtitle": subtitle as Any, "style": style, "accessoryType": accessoryType, "tapped": tapped as Any]
        return "\(desc) \(props)"
    }
}

/// Models a section in a table. Contains many `TableRowData` objects.
class TableSectionData: NSObject, ListDiffable {

    let title: String?
    let rows: [TableRowData]
    let backgroundColor: UIColor?

    func diffIdentifier() -> NSObjectProtocol {
        return self
    }

    func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let rhs = object as? TableSectionData else {
            return false
        }

        return title == rhs.title && rows == rhs.rows && backgroundColor == rhs.backgroundColor
    }

    public init(title: String?, rows: [TableRowData], backgroundColor: UIColor? = nil) {
        self.title = title
        self.rows = rows
        self.backgroundColor = backgroundColor
        super.init()
    }
}
