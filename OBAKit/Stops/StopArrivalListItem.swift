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

extension ArrivalDeparture: ListDiffable {
    public func diffIdentifier() -> NSObjectProtocol {
        return self
    }

    public func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        return isEqual(object)
    }
}

// MARK: - Controller

final class StopArrivalSectionController: ListSectionController {
    private var object: ArrivalDeparture?
    private let formatters: Formatters

    override func sizeForItem(at index: Int) -> CGSize {
        return CGSize(width: collectionContext!.containerSize.width, height: 40)
    }

    override func cellForItem(at index: Int) -> UICollectionViewCell {
        guard let cell = collectionContext?.dequeueReusableCell(of: StopArrivalCell.self, for: self, at: index) as? StopArrivalCell else {
            fatalError()
        }
        cell.formatters = formatters
        cell.arrivalDeparture = object
        return cell
    }

    override func didUpdate(to object: Any) {
        self.object = (object as! ArrivalDeparture) // swiftlint:disable:this force_cast
    }

    init(formatters: Formatters) {
        self.formatters = formatters
        super.init()
        inset = .zero
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
                contentView.addSubview(stopArrivalView)

                NSLayoutConstraint.activate([
                    stopArrivalView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
                    stopArrivalView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
                    stopArrivalView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: ThemeMetrics.tableHeaderTopPadding),
                    stopArrivalView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
                ])
            }
        }
    }
}
