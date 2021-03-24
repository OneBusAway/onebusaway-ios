//
//  StopArrivalCell.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

final class StopArrivalCell: OBAListViewCell {
    // MARK: - Properties for showing swipe actions nudge
    var canCreateAlarmForArrivalDeparture: Bool = false
    var isShowingPastArrivalDeparture: Bool = false

    // MARK: - View properties
    private var highlightTimeOnDisplay: Bool = false
    private var stopArrivalView: StopArrivalView!

    override var accessibilityElements: [Any]? {
        get { return [stopArrivalView as Any] }
        set { _ = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        fixiOS13AutoLayoutBug()
        contentView.backgroundColor = ThemeColors.shared.systemBackground

        stopArrivalView = StopArrivalView.autolayoutNew()
        stopArrivalView.backgroundColor = .clear
        contentView.addSubview(stopArrivalView)

        stopArrivalView.pinToSuperview(.readableContent) { constraints in
            constraints.trailing.priority = .required - 1
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI
    override func apply(_ config: OBAContentConfiguration) {
        guard let config = config as? ArrivalDepartureContentConfiguration else { return }
        canCreateAlarmForArrivalDeparture = config.viewModel.isAlarmAvailable
        isShowingPastArrivalDeparture = config.viewModel.temporalState == .past
        highlightTimeOnDisplay = config.viewModel.highlightTimeOnDisplay
        stopArrivalView.configureView(for: config)
    }

    override func willDisplayCell(in listView: OBAListView) {
        if highlightTimeOnDisplay {
            stopArrivalView.minutesLabel.highlightBackground()
            highlightTimeOnDisplay = false
        }
    }

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
