//
//  WalkTimeSection.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 4/7/20.
//

import UIKit
import IGListKit
import OBAKitCore
import CoreLocation

/// IGListKit section data class that displays a `WalkTimeView`.
final class WalkTimeSectionData: NSObject, ListDiffable {
    func diffIdentifier() -> NSObjectProtocol {
        return self
    }

    func isEqual(toDiffableObject object: ListDiffable?) -> Bool {
        guard let object = object as? WalkTimeSectionData else { return false }
        return distance == object.distance && timeToWalk == object.timeToWalk
    }

    init(distance: CLLocationDistance, timeToWalk: TimeInterval) {
        self.distance = distance
        self.timeToWalk = timeToWalk
    }

    let distance: CLLocationDistance
    let timeToWalk: TimeInterval
}

/// A IGListKit section controller that works with `WalkTimeSectionData` to display a `WalkTimeView`.
final class WalkTimeSectionController: OBAListSectionController<WalkTimeSectionData> {
    override func cellForItem(at index: Int) -> UICollectionViewCell {
        guard let sectionData = sectionData else { fatalError() }

        let cell = dequeueReusableCell(type: WalkTimeCell.self, at: index)
        cell.walkTimeView.formatters = formatters
        cell.walkTimeView.set(distance: sectionData.distance, timeToWalk: sectionData.timeToWalk)
        return cell
    }
}

/// A collection view cell that works with `WalkTimeSectionData` to display a `WalkTimeView`.
final class WalkTimeCell: SelfSizingCollectionCell {
    let walkTimeView = WalkTimeView.autolayoutNew()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(walkTimeView)
        walkTimeView.pinToSuperview(.edges)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }
}
