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

final public class TableSectionController: ListSectionController, ListSupplementaryViewSource, SwipeCollectionViewCellDelegate {
    var data: TableSectionData?

    private let style: CollectionControllerStyle

    public init(style: CollectionControllerStyle = .plain) {
        self.style = style
        super.init()
        supplementaryViewSource = self
    }

    public override func sizeForItem(at index: Int) -> CGSize {
        return CGSize(width: collectionContext!.containerSize.width, height: 40.0)
    }

    public override func numberOfItems() -> Int {
        return data?.rows.count ?? 0
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
            let rowData = data?.rows[index],
            let cell = collectionContext?.dequeueReusableCell(of: cellClass(for: rowData), for: self, at: index) as? TableRowCell
        else {
            fatalError()
        }

        cell.delegate = self
        cell.data = rowData
        cell.style = style
        cell.collapseLeftInset = (index == numberOfItems() - 1)

        return cell
    }

    public override func didUpdate(to object: Any) {
        precondition(object is TableSectionData)
        data = object as? TableSectionData
    }

    public override func didSelectItem(at index: Int) {
        guard
            let item = data?.rows[index],
            let tapped = item.tapped
        else {
            return
        }

        tapped(item)
    }

    // MARK: ListSupplementaryViewSource

    public func supportedElementKinds() -> [String] {
        var supported = [String]()

        if data?.title != nil {
            supported.append(UICollectionView.elementKindSectionHeader)
        }

        if data?.footer != nil {
            supported.append(UICollectionView.elementKindSectionFooter)
        }

        return supported
    }

    public func viewForSupplementaryElement(ofKind elementKind: String, at index: Int) -> UICollectionReusableView {
        switch elementKind {
        case UICollectionView.elementKindSectionHeader:
            return buildHeaderView(atIndex: index)
        case UICollectionView.elementKindSectionFooter:
            return buildFooterView(atIndex: index)
        default:
            fatalError()
        }
    }

    public func sizeForSupplementaryView(ofKind elementKind: String, at index: Int) -> CGSize {
        let height: CGFloat = style == .grouped ? 32 : 20
        return CGSize(width: collectionContext!.containerSize.width, height: height)
    }

    // MARK: - SwipeCollectionViewCellDelegate

    public func collectionView(_ collectionView: UICollectionView, editActionsForItemAt indexPath: IndexPath, for orientation: SwipeActionsOrientation) -> [SwipeAction]? {
        guard
            orientation == .right,
            let row = data?.rows[indexPath.item],
            let deleteHandler = row.deleted
        else {
            return nil
        }

        let deleteAction = SwipeAction(style: .destructive, title: Strings.delete) { _, _ in
            deleteHandler(row)
        }

        return [deleteAction]
    }

    // MARK: - Private

    private func buildHeaderView(atIndex index: Int) -> UICollectionReusableView {
        guard let view = collectionContext?.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, for: self, class: TableSectionHeaderView.self, at: index) as? TableSectionHeaderView else {
            fatalError()
        }

        view.textLabel.text = data?.title ?? ""
        view.isGrouped = style == .grouped

        return view
    }

    private func buildFooterView(atIndex index: Int) -> UICollectionReusableView {
        guard let view = collectionContext?.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, for: self, class: TableSectionHeaderView.self, at: index) as? TableSectionHeaderView else {
            fatalError()
        }

        view.textLabel.text = data?.footer ?? ""
        return view
    }
}
