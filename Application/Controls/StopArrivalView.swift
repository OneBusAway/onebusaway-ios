//
//  StopArrivalView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/6/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit

@objc(OBAStopArrivalView)
public class StopArrivalView: UIView {
    let routeHeadsignLabel = UILabel.autolayoutNew()
    let timeLabel = UILabel.autolayoutNew()

    private var _formatters: Formatters!
    @objc dynamic var formatters: Formatters {
        get { return _formatters }
        set { _formatters = newValue }
    }

    @objc public var arrivalDeparture: ArrivalDeparture! {
        didSet {
            routeHeadsignLabel.text = arrivalDeparture.routeAndHeadsign

            // 'Gray out' the view if it occurred in the past.
            alpha = arrivalDeparture.temporalStateOfArrivalDepartureDate == .past ? 0.50 : 1.0

            let timeText = formatters.timeFormatter.string(from: arrivalDeparture.arrivalDepartureDate)
            let explanationText = formatters.explanation(from: arrivalDeparture)
            timeLabel.text = "\(timeText) - \(explanationText)"
        }
    }

    @objc override init(frame: CGRect) {
        super.init(frame: frame)

        let stack = UIStackView.verticalStack(arangedSubviews: [routeHeadsignLabel, timeLabel])
        addSubview(stack)
        stack.pinToSuperview(.edges)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

