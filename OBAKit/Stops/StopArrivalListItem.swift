//
//  StopArrivalListItem.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 8/6/19.
//

import IGListKit
import UIKit
import OBAKitCore

// MARK: - View Model

final class ArrivalDepartureSectionData: NSObject, ListDiffable {
    let arrivalDeparture: ArrivalDeparture
    let selected: VoidBlock

    init(arrivalDeparture: ArrivalDeparture, selected: @escaping VoidBlock) {
        self.arrivalDeparture = arrivalDeparture
        self.selected = selected
    }

    public func diffIdentifier() -> NSObjectProtocol {
        return self
    }

    public func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let object = object as? ArrivalDepartureSectionData else { return false }
        return arrivalDeparture == object.arrivalDeparture
    }
}

// MARK: - Controller

final class StopArrivalSectionController: OBAListSectionController<ArrivalDepartureSectionData> {

    override func cellForItem(at index: Int) -> UICollectionViewCell {
        guard let object = sectionData else { fatalError() }

        let cell = dequeueReusableCell(type: StopArrivalCell.self, at: index)
        cell.formatters = formatters
        cell.arrivalDeparture = object.arrivalDeparture
        return cell
    }

    override func didSelectItem(at index: Int) {
        guard let sectionData = sectionData else { return }
        sectionData.selected()
    }
}

// MARK: - View

final class StopArrivalCell: BaseSelfSizingTableCell {
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
}
