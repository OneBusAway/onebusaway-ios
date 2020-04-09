//
//  StopArrivalListItem.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 8/6/19.
//

import IGListKit
import UIKit
import OBAKitCore
import SwipeCellKit

// MARK: - View Model

final class ArrivalDepartureSectionData: NSObject, ListDiffable {
    let arrivalDeparture: ArrivalDeparture
    let isAlarmAvailable: Bool
    let selected: VoidBlock
    var onCreateAlarm: VoidBlock?
    var onShowOptions: VoidBlock?

    init(arrivalDeparture: ArrivalDeparture, isAlarmAvailable: Bool = false, selected: @escaping VoidBlock) {
        self.arrivalDeparture = arrivalDeparture
        self.isAlarmAvailable = isAlarmAvailable
        self.selected = selected
    }

    public func diffIdentifier() -> NSObjectProtocol {
        return self
    }

    public func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let object = object as? ArrivalDepartureSectionData else { return false }
        return arrivalDeparture == object.arrivalDeparture && isAlarmAvailable == object.isAlarmAvailable
    }
}

// MARK: - Controller

final class StopArrivalSectionController: OBAListSectionController<ArrivalDepartureSectionData>, SwipeCollectionViewCellDelegate {

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
            sectionData.onShowOptions?()
        }
        moreActions.font = UIFont.preferredFont(forTextStyle: .caption1)
        moreActions.backgroundColor = ThemeColors.shared.green
        moreActions.image = Icons.showMore
        actions.append(moreActions)

        return actions
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

    var formatters: Formatters! {
        didSet {
            if stopArrivalView == nil {
                stopArrivalView = StopArrivalView.autolayoutNew()
                stopArrivalView.formatters = formatters
                stopArrivalView.backgroundColor = .clear
                contentView.addSubview(stopArrivalView)
                stopArrivalView.pinToSuperview(.layoutMargins)
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        fixiOS13AutoLayoutBug()
        contentView.layer.addSublayer(separator)
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

    func showNudge() {
        showSwipe(orientation: .right)
    }
}
