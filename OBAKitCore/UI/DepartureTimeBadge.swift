//
//  DepartureTimeBadge.swift
//  OBAKit
//
//  Created by Alan Chu on 12/22/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit

/// A rounded time badge representing the provided upcoming departure time and deviation status.
public class DepartureTimeBadge: UILabel, ArrivalDepartureDrivenUI {
    /// Defines the margin for the text. By default, this is `ThemeMetrics.compactPadding` for
    /// Top and Bottom and `ThemeMetrics.buttonContentPadding` for Left and Right.
    public var contentMargin: UIEdgeInsets = UIEdgeInsets(top: ThemeMetrics.compactPadding,
                                                          left: ThemeMetrics.buttonContentPadding,
                                                          bottom: ThemeMetrics.compactPadding,
                                                          right: ThemeMetrics.buttonContentPadding)

    public override var intrinsicContentSize: CGSize {
        // Account for the content margin added in drawText(:_) override.
        var size = super.intrinsicContentSize
        size.width += contentMargin.left + contentMargin.right
        size.height += contentMargin.top + contentMargin.bottom
        return size
    }

    public var highlightedBackgroundColor: UIColor = ThemeColors.shared.propertyChanged

    public override init(frame: CGRect) {
        super.init(frame: frame)

        textColor = ThemeColors.shared.lightText

        textAlignment = .center
        font = UIFont.preferredFont(forTextStyle: .headline)

        layer.backgroundColor = UIColor.clear.cgColor
        layer.masksToBounds = true
        layer.cornerRadius = 8
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func drawText(in rect: CGRect) {
        // Include the content margin.
        super.drawText(in: rect.inset(by: contentMargin))
    }

    public func prepareForReuse() {
        accessibilityLabel = nil
        text = nil
    }

    public func configure(with arrivalDeparture: ArrivalDeparture, formatters: Formatters) {
        accessibilityLabel = formatters.formattedTime(until: arrivalDeparture)
        text = formatters.shortFormattedTime(until: arrivalDeparture)

        let status = arrivalDeparture.scheduleStatus
        layer.backgroundColor = formatters.backgroundColorForScheduleStatus(status).cgColor
    }

    public func highlightBackground() {
        let oldBackgroundColor = layer.backgroundColor
        layer.backgroundColor = highlightedBackgroundColor.cgColor

        UIView.animate(withDuration: 2.0) { [weak self] in
            self?.layer.backgroundColor = oldBackgroundColor
        }
    }
}
