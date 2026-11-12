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
    // MARK: - View properties
    private var stopArrivalView: StopArrivalView!

    override var accessibilityElements: [Any]? {
        get { return [stopArrivalView as Any] }
        set { _ = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

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
        stopArrivalView.configureView(for: config)
    }
}
