//
//  TableSectionController.swift
//  OBANext
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import IGListKit
import SwipeCellKit
import OBAKitCore

// MARK: - TableRowData

/// Models a single table row
class TableRowData: ListViewModel {

    let title: String?
    let attributedTitle: NSAttributedString?

    let subtitle: String?
    let accessoryType: UITableViewCell.AccessoryType
    let style: UITableViewCell.CellStyle

    public var image: UIImage?
    public var imageSize: CGFloat?

    /// Generates the preview view controller for a `UIContextMenu`.
    var previewDestination: (() -> UIViewController?)?

    /// Generates the `UIMenu`. This block must return a `UIMenu` object or `nil`. `Any?` return type in block is due to the need to support iOS 12.
    var buildContextMenu: (() -> Any?)?

    // MARK: - Initialization

    /// Default Initializer. Lets you set everything.
    ///
    /// - Parameters:
    ///   - title: The title of the row. Optional.
    ///   - attributedTitle: The attributed title of the row. Optional.
    ///   - subtitle: The subtitle of the row. Optional.
    ///   - style: The style (appearance/layout) of the row.
    ///   - accessoryType: The accessory type on the right side, if any.
    ///   - tapped: Tap event handler.
    public init(title: String?, attributedTitle: NSAttributedString?, subtitle: String?, style: UITableViewCell.CellStyle, accessoryType: UITableViewCell.AccessoryType, tapped: ListRowActionHandler?) {
        self.title = title
        self.attributedTitle = attributedTitle
        self.subtitle = subtitle
        self.style = style
        self.accessoryType = accessoryType

        super.init(tapped: tapped)
    }

    /// Create a default-style row with an attributed string title.
    ///
    /// - Parameters:
    ///   - attributedTitle: The attributed string title.
    ///   - accessoryType: The accessory type on the right side, if any.
    ///   - tapped: Tap event handler.
    convenience init(attributedTitle: NSAttributedString, accessoryType: UITableViewCell.AccessoryType, tapped: ListRowActionHandler?) {
        self.init(title: nil, attributedTitle: attributedTitle, subtitle: nil, style: .default, accessoryType: accessoryType, tapped: tapped)
    }

    /// Create a default-style row with an accessory.
    ///
    /// - Parameters:
    ///   - title: The title for the row.
    ///   - accessoryType: The accessory type of the row.
    ///   - tapped: Tap event handler
    convenience init(title: String, accessoryType: UITableViewCell.AccessoryType, tapped: ListRowActionHandler?) {
        self.init(title: title, attributedTitle: nil, subtitle: nil, style: .default, accessoryType: accessoryType, tapped: tapped)
    }

    /// Create a subtitle-style row with an accessory.
    ///
    /// - Parameters:
    ///   - title: The title for the row.
    ///   - subtitle: The subtitle for the row.
    ///   - accessoryType: The accessory type.
    ///   - tapped: Tap event handler.
    convenience init(title: String, subtitle: String, accessoryType: UITableViewCell.AccessoryType, tapped: ListRowActionHandler?) {
        self.init(title: title, attributedTitle: nil, subtitle: subtitle, style: .subtitle, accessoryType: accessoryType, tapped: tapped)
    }

    /// Create a value-style row with an accessory.
    ///
    /// - Parameters:
    ///   - title: The title for the row.
    ///   - values: The value for the row.
    ///   - accessoryType: The accessory type.
    ///   - tapped: Tap event handler.
    convenience init(title: String, value: String?, accessoryType: UITableViewCell.AccessoryType, tapped: ListRowActionHandler?) {
        self.init(title: title, attributedTitle: nil, subtitle: value, style: .value1, accessoryType: accessoryType, tapped: tapped)
    }

    // MARK: - Object Methods

    override public var debugDescription: String {
        let desc = super.debugDescription
        let props: [String: Any] = ["title": title as Any, "subtitle": subtitle as Any, "style": style, "accessoryType": accessoryType]
        return "\(desc) \(props)"
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? TableRowData else { return false }

        return
            title == rhs.title &&
            attributedTitle == rhs.attributedTitle &&
            subtitle == rhs.subtitle &&
            accessoryType == rhs.accessoryType &&
            style == rhs.style &&
            image == rhs.image
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(title)
        hasher.combine(attributedTitle)
        hasher.combine(subtitle)
        hasher.combine(accessoryType)
        hasher.combine(style)
        hasher.combine(image)
        return hasher.finalize()
    }
}

// MARK: - TableSectionData

/// Models a section in a table. Contains many `TableRowData` objects.
class TableSectionData: NSObject, ListDiffable {
    let rows: [TableRowData]

    public func diffIdentifier() -> NSObjectProtocol {
        return self
    }

    public func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let rhs = object as? TableSectionData else {
            return false
        }

        return rows == rhs.rows
    }

    /// Creates a `TableSectionData`
    /// - Parameter rows: The table rows
    public init(rows: [TableRowData]) {
        self.rows = rows
        super.init()
    }

    /// Convenience initializer for creating a `TableSectionData` with a single row.
    /// - Parameter row: The single table row.
    convenience init(row: TableRowData) {
        self.init(rows: [row])
    }
}

// MARK: - TableSectionController

final class TableSectionController: OBAListSectionController<TableSectionData>, SwipeCollectionViewCellDelegate, ContextMenuProvider {
    public override func numberOfItems() -> Int {
        return sectionData?.rows.count ?? 0
    }

    private func cellClass(for rowData: TableRowData) -> TableRowCell.Type {
        switch rowData.style {
        case .default: return DefaultTableCell.self
        case .value1, .value2: return ValueTableCell.self
        case .subtitle: return SubtitleTableCell.self
        @unknown default:
            return DefaultTableCell.self
        }
    }

    public override func cellForItem(at index: Int) -> UICollectionViewCell {
        guard let rowData = sectionData?.rows[index] else { fatalError() }

        let cell = dequeueReusableCell(type: cellClass(for: rowData), at: index)
        cell.delegate = self
        cell.data = rowData
        cell.style = style
        cell.collapseLeftInset = style == .grouped ? (index == numberOfItems() - 1) : false

        return cell
    }

    public override func didSelectItem(at index: Int) {
        guard
            let item = sectionData?.rows[index],
            let tapped = item.tapped
        else {
            return
        }

        tapped(item)
    }

    // MARK: - SwipeCollectionViewCellDelegate

    public func collectionView(_ collectionView: UICollectionView, editActionsForItemAt indexPath: IndexPath, for orientation: SwipeActionsOrientation) -> [SwipeAction]? {
        guard
            orientation == .right,
            let row = sectionData?.rows[indexPath.item],
            let deleteHandler = row.deleted
        else {
            return nil
        }

        let deleteAction = SwipeAction(style: .destructive, title: Strings.delete) { _, _ in
            deleteHandler(row)
        }

        return [deleteAction]
    }

    // MARK: - Context Menu
    func contextMenuConfiguration(forItemAt indexPath: IndexPath) -> UIContextMenuConfiguration? {
        guard let sectionData = self.sectionData else { return nil }
        let tableRow = sectionData.rows[indexPath.item]

        // Check if there is a destination, but don't initialize it yet.
        guard let destination = tableRow.previewDestination else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: {
            // Try initializing the destination view controller. If it doesn't work,
            // it will gracefully return `nil`.
            let controller = destination()
            if let previewable = controller as? Previewable {
                previewable.enterPreviewMode()
            }
            return controller
        }, actionProvider: { _ -> UIMenu? in
            if let menu = tableRow.buildContextMenu?() as? UIMenu {
                return menu
            }
            else {
                return nil
            }
        })
    }
}
