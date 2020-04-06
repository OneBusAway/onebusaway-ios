//
//  TableSectionController.swift
//  OBANext
//
//  Created by Aaron Brethorst on 1/13/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit
import IGListKit
import SwipeCellKit
import OBAKitCore

final class TableSectionController: OBAListSectionController<TableSectionData>, SwipeCollectionViewCellDelegate {
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
        guard
            let rowData = sectionData?.rows[index],
            let cell = collectionContext?.dequeueReusableCell(of: cellClass(for: rowData), for: self, at: index) as? TableRowCell
        else {
            fatalError()
        }

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
}
