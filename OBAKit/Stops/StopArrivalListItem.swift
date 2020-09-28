//
//  StopArrivalListItem.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import IGListKit
import UIKit
import OBAKitCore
import SwipeCellKit

// MARK: - View Model

/// This view model is used to display an `ArrivalDeparture` object within a `StopArrivalCell` in an IGListKit collection view.
final class ArrivalDepartureSectionData: NSObject, ListDiffable {
    let arrivalDeparture: ArrivalDeparture
    let isAlarmAvailable: Bool
    /// Creates an instance of `ArrivalDepartureSectionData`.
    /// - Parameters:
    ///   - arrivalDeparture: The trip arrival/departure information to display.
    ///   - isAlarmAvailable: Whether or not the UI to create an alarm should be displayed.
    init(arrivalDeparture: ArrivalDeparture, isAlarmAvailable: Bool = false) {
        self.arrivalDeparture = arrivalDeparture
        self.isAlarmAvailable = isAlarmAvailable
    }

    public func diffIdentifier() -> NSObjectProtocol {
        return self.arrivalDeparture.id as NSString
    }

    public func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let object = object as? ArrivalDepartureSectionData else { return false }
        return arrivalDeparture == object.arrivalDeparture && isAlarmAvailable == object.isAlarmAvailable
    }
}

// MARK: - Controller Delegate
protocol StopArrivalSectionControllerDelegate: class {
    func stopArrivalSectionController(_ controller: StopArrivalSectionController, didSelect arrivalDeparture: ArrivalDepartureSectionData)
    func stopArrivalSectionController(_ controller: StopArrivalSectionController, shouldHighlightOnAppearance arrivalDeparture: ArrivalDepartureSectionData) -> Bool
    func stopArrivalSectionController(_ controller: StopArrivalSectionController, swipeActionsFor arrivalDeparture: ArrivalDepartureSectionData) -> [SwipeAction]?

    @available(iOS 13, *)
    func stopArrivalSectionController(_ controller: StopArrivalSectionController, contextMenuConfigurationFor arrivalDeparture: ArrivalDepartureSectionData) -> UIContextMenuConfiguration?
}

// MARK: Default implementations
extension StopArrivalSectionControllerDelegate {
    func stopArrivalSectionController(_ controller: StopArrivalSectionController, shouldHighlightOnAppearance arrivalDeparture: ArrivalDepartureSectionData) -> Bool {
        return false
    }

    func stopArrivalSectionController(_ controller: StopArrivalSectionController, swipeActionsFor arrivalDeparture: ArrivalDepartureSectionData) -> [SwipeAction]? {
        return nil
    }

    @available(iOS 13, *)
    func stopArrivalSectionController(_ controller: StopArrivalSectionController, contextMenuConfigurationFor arrivalDeparture: ArrivalDepartureSectionData) -> UIContextMenuConfiguration? {
        return nil
    }
}

// MARK: - Controller
final class StopArrivalSectionController: OBAListSectionController<ArrivalDepartureSectionData>,
    ContextMenuProvider,
    SwipeCollectionViewCellDelegate {
    weak var delegate: StopArrivalSectionControllerDelegate?

    override func cellForItem(at index: Int) -> UICollectionViewCell {
        guard let object = sectionData else { fatalError() }

        let cell = dequeueReusableCell(type: StopArrivalCell.self, at: index)
        cell.formatters = formatters
        cell.delegate = self
        cell.arrivalDeparture = object.arrivalDeparture
        return cell
    }

    override func didSelectItem(at index: Int) {
        guard let sectionData = sectionData else { return }
        delegate?.stopArrivalSectionController(self, didSelect: sectionData)
    }

    override func listAdapter(_ listAdapter: ListAdapter, willDisplay sectionController: ListSectionController, cell: UICollectionViewCell, at index: Int) {
        guard let object = sectionData else { fatalError() }

        guard let cell = cell as? StopArrivalCell,
            let delegate = self.delegate else { return }

        if delegate.stopArrivalSectionController(self, shouldHighlightOnAppearance: object) {
            cell.highlightMinutes()
        }
    }

    // MARK: - SwipeCollectionViewCellDelegate

    public func collectionView(_ collectionView: UICollectionView, editActionsForItemAt indexPath: IndexPath, for orientation: SwipeActionsOrientation) -> [SwipeAction]? {
        guard
            orientation == .right,
            let sectionData = sectionData
        else { return nil }

        return delegate?.stopArrivalSectionController(self, swipeActionsFor: sectionData)
    }

    // MARK: - Context Menu

    func contextMenuConfiguration(forItemAt indexPath: IndexPath) -> UIContextMenuConfiguration? {
        guard let sectionData = self.sectionData else { return nil }
        return delegate?.stopArrivalSectionController(self, contextMenuConfigurationFor: sectionData)
    }
}

// MARK: - View

final class StopArrivalCell: SwipeCollectionViewCell, SelfSizing, Separated {
    var arrivalDeparture: ArrivalDeparture? {
        didSet {
            guard let arrivalDeparture = arrivalDeparture else { return }
            stopArrivalView.arrivalDeparture = arrivalDeparture
        }
    }

    private var stopArrivalView: StopArrivalView!

    override var accessibilityElements: [Any]? {
        get { return [stopArrivalView as Any] }
        set { _ = newValue }
    }

    var formatters: Formatters! {
        didSet {
            if stopArrivalView == nil {
                stopArrivalView = StopArrivalView.autolayoutNew()
                stopArrivalView.formatters = formatters
                stopArrivalView.backgroundColor = .clear
                contentView.addSubview(stopArrivalView)

                stopArrivalView.pinToSuperview(.readableContent) { constraints in
                    constraints.trailing.priority = .required - 1
                }
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        fixiOS13AutoLayoutBug()
        contentView.layer.addSublayer(separator)
        contentView.backgroundColor = ThemeColors.shared.systemBackground
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Separator

    let separator = tableCellSeparatorLayer()

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSeparator()
    }

    // MARK: - Self Sizing

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        return calculateLayoutAttributesFitting(layoutAttributes)
    }

    // MARK: - UI

    func highlightMinutes() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.stopArrivalView.minutesLabel.highlightBackground()
        }
    }

    func showNudge() {
        showSwipe(orientation: .right)
    }
}
