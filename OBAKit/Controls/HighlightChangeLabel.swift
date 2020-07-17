//
//  HighlightChangeLabel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import OBAKitCore

/// Alerts the user when its value changes by temporarily changing its background color.
class HighlightChangeLabel: UILabel, ArrivalDepartureDrivenUI {
    override public init(frame: CGRect) {
        super.init(frame: frame)
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        setContentHuggingPriority(.required - 1, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var text: String? {
        didSet {
            guard oldValue != text else { return }

            if oldValue != nil {
                highlightBackground()
            }
        }
    }

    /// This is the color that is used to highlight a value change in this label.
    var highlightedBackgroundColor: UIColor = ThemeColors.shared.propertyChanged

    /// Causes the background of the label to be highlighted for `Animations.longAnimationDuration`.
    public func highlightBackground() {
        let oldBackgroundColor = layer.backgroundColor
        layer.backgroundColor = highlightedBackgroundColor.cgColor

        Animations.performAnimations(duration: Animations.longAnimationDuration) { [weak self] in
            guard let self = self else { return }
            self.layer.backgroundColor = oldBackgroundColor
        }
    }

    func configure(with arrivalDeparture: ArrivalDeparture, formatters: Formatters) {
        self.text = formatters.shortFormattedTime(until: arrivalDeparture)
        self.textColor = formatters.colorForScheduleStatus(arrivalDeparture.scheduleStatus)
    }
}
