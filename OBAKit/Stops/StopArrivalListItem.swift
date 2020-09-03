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
    let highlightOnAppearance: Bool
    let selected: VoidBlock

    var onCreateAlarm: VoidBlock?
    var onShowOptions: ((UIView?, CGRect?) -> Void)?
    var onAddBookmark: VoidBlock?
    var onShareTrip: VoidBlock?

    var previewDestination: ControllerPreviewProvider?

    /// Creates an instance of `ArrivalDepartureSectionData`.
    /// - Parameters:
    ///   - arrivalDeparture: The trip arrival/departure information to display.
    ///   - isAlarmAvailable: Whether or not the UI to create an alarm should be displayed.
    ///   - highlightOnAppearance: Whether or not the 'minutes until arrival/departure' label should flash.
    ///   - selected: An 'on tap' handler.
    init(arrivalDeparture: ArrivalDeparture, isAlarmAvailable: Bool = false, highlightOnAppearance: Bool = false, selected: @escaping VoidBlock) {
        self.arrivalDeparture = arrivalDeparture
        self.isAlarmAvailable = isAlarmAvailable
        self.highlightOnAppearance = highlightOnAppearance
        self.selected = selected
    }

    public func diffIdentifier() -> NSObjectProtocol {
        return self.arrivalDeparture.arrivalDepartureID as NSString
    }

    public func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let object = object as? ArrivalDepartureSectionData else { return false }
        return arrivalDeparture == object.arrivalDeparture && isAlarmAvailable == object.isAlarmAvailable && highlightOnAppearance == object.highlightOnAppearance
    }
}

// MARK: - Controller

final class StopArrivalSectionController: OBAListSectionController<ArrivalDepartureSectionData>,
    ContextMenuProvider,
    SwipeCollectionViewCellDelegate {

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
        sectionData.selected()
    }

    override func listAdapter(_ listAdapter: ListAdapter, willDisplay sectionController: ListSectionController, cell: UICollectionViewCell, at index: Int) {
        guard let object = sectionData else { fatalError() }

        if let cell = cell as? StopArrivalCell, object.highlightOnAppearance {
            cell.highlightMinutes()
        }
    }

    // MARK: - SwipeCollectionViewCellDelegate

    public func collectionView(_ collectionView: UICollectionView, editActionsForItemAt indexPath: IndexPath, for orientation: SwipeActionsOrientation) -> [SwipeAction]? {
        guard
            orientation == .right,
            let sectionData = sectionData
        else { return nil }

        var actions = [SwipeAction]()

        if sectionData.isAlarmAvailable {
            let addAlarm = SwipeAction(style: .default, title: Strings.alarm) { (_, _) in
                sectionData.onCreateAlarm?()
            }
            addAlarm.backgroundColor = ThemeColors.shared.blue
            addAlarm.font = UIFont.preferredFont(forTextStyle: .caption1)
            addAlarm.image = Icons.addAlarm
            actions.append(addAlarm)
        }

        let moreActions = SwipeAction(style: .default, title: Strings.more) { (_, _) in
            let cell = collectionView.cellForItem(at: indexPath)
            var frame = collectionView.layoutAttributesForItem(at: indexPath)?.bounds ?? .zero
            frame.origin.x = frame.width - 110.0

            sectionData.onShowOptions?(cell, frame)
        }
        moreActions.font = UIFont.preferredFont(forTextStyle: .caption1)
        moreActions.backgroundColor = ThemeColors.shared.green
        moreActions.image = Icons.showMore
        actions.append(moreActions)

        return actions
    }

    // MARK: - Context Menu

    @available(iOS 13.0, *)
    func contextMenuConfiguration(forItemAt indexPath: IndexPath) -> UIContextMenuConfiguration? {
        let previewProvider = { [weak self] () -> UIViewController? in
            guard
                let self = self,
                let sectionData = self.sectionData
            else { return nil }

            let controller = sectionData.previewDestination?()

            if let previewable = controller as? Previewable {
                previewable.enterPreviewMode()
            }

            return controller
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: previewProvider) { [weak self] _ in
            guard
                let self = self,
                let sectionData = self.sectionData
            else { return nil }

            var actions = [UIAction]()

            if sectionData.isAlarmAvailable {
                let alarm = UIAction(title: Strings.addAlarm, image: Icons.addAlarm) { _ in
                    sectionData.onCreateAlarm?()
                }
                actions.append(alarm)
            }

            let addBookmark = UIAction(title: Strings.addBookmark, image: Icons.addBookmark) { _ in
                sectionData.onAddBookmark?()
            }
            actions.append(addBookmark)

            let shareTrip = UIAction(title: Strings.shareTrip, image: UIImage(systemName: "square.and.arrow.up")) { _ in
                sectionData.onShareTrip?()
            }
            actions.append(shareTrip)

            // Create and return a UIMenu with all of the actions as children
            return UIMenu(title: "", children: actions)
        }
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
