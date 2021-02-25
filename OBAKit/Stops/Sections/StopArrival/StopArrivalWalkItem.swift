//
//  StopArrivalWalkItem.swift
//  OBAKit
//
//  Created by Alan Chu on 2/24/21.
//

import OBAKitCore
import CoreLocation

struct StopArrivalWalkItem: OBAListViewItem {
    var contentConfiguration: OBAContentConfiguration {
        return StopArrivalWalkContentConfiguration(distance: distance, timeToWalk: timeToWalk)
    }

    static var customCellType: OBAListViewCell.Type? {
        return StopArrivalWalkCell.self
    }

    var onSelectAction: OBAListViewAction<StopArrivalWalkItem>?

    let id: String
    let distance: CLLocationDistance
    let timeToWalk: TimeInterval

    static func == (lhs: StopArrivalWalkItem, rhs: StopArrivalWalkItem) -> Bool {
        return lhs.id == rhs.id &&
            lhs.distance == rhs.distance &&
            lhs.timeToWalk == rhs.timeToWalk
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct StopArrivalWalkContentConfiguration: OBAContentConfiguration {
    var distance: CLLocationDistance
    var timeToWalk: TimeInterval
    var formatters: Formatters?

    var obaContentView: (OBAContentView & ReuseIdentifierProviding).Type {
        return StopArrivalWalkCell.self
    }
}

class StopArrivalWalkCell: OBAListViewCell {
    override var showsSeparator: Bool {
        return false
    }

    let walkTimeView = WalkTimeView.autolayoutNew()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(walkTimeView)
        walkTimeView.pinToSuperview(.edges)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    override func apply(_ config: OBAContentConfiguration) {
        guard let config = config as? StopArrivalWalkContentConfiguration else { return }
        walkTimeView.formatters = config.formatters
        walkTimeView.set(distance: config.distance, timeToWalk: config.timeToWalk)
    }
}
