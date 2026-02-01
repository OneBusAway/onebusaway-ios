//
//  DepartureTimeBadge.swift
//  OBAKit
//
//  Created by Alan Chu on 12/22/19.
//  Copyright © 2019 OneBusAway. All rights reserved.
//

import UIKit
import OBAKitCore

/// A rounded time badge representing the provided upcoming departure time and deviation status.
public class DepartureTimeBadge: UILabel, ArrivalDepartureDrivenUI {
    public struct Configuration: Hashable, Equatable {
        var accessibilityLabel: String
        var displayText: String
        var backgroundColor: CGColor

        public init(arrivalDepartureMinutes: Int,
                    arrivalDepartureStatus: ArrivalDepartureStatus,
                    temporalState: TemporalState,
                    scheduleStatus: ScheduleStatus,
                    formatters: Formatters) {
            self.accessibilityLabel = formatters.explanationForArrivalDeparture(tempuraState: temporalState, arrivalDepartureStatus: arrivalDepartureStatus, arrivalDepartureMinutes: arrivalDepartureMinutes)
            self.displayText = formatters.shortFormattedTime(untilMinutes: arrivalDepartureMinutes, temporalState: temporalState)
            self.backgroundColor = formatters.backgroundColorForScheduleStatus(scheduleStatus).cgColor
        }

        public init(withArrivalDeparture arrivalDeparture: ArrivalDeparture, formatters: Formatters) {
            self.init(arrivalDepartureMinutes: arrivalDeparture.arrivalDepartureMinutes,
                      arrivalDepartureStatus: arrivalDeparture.arrivalDepartureStatus,
                      temporalState: arrivalDeparture.temporalState,
                      scheduleStatus: arrivalDeparture.scheduleStatus,
                      formatters: formatters)
        }

        public init(accessibilityLabel: String, displayText: String, backgroundColor: CGColor) {
            self.accessibilityLabel = accessibilityLabel
            self.displayText = displayText
            self.backgroundColor = backgroundColor
        }
    }

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
        adjustsFontSizeToFitWidth = true

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
        layer.backgroundColor = nil
    }

    public func configure(with arrivalDeparture: ArrivalDeparture, formatters: Formatters) {
        self.configure(Configuration(withArrivalDeparture: arrivalDeparture, formatters: formatters))
    }

    public func configure(_ config: Configuration?) {
        accessibilityLabel = config?.accessibilityLabel
        text = config?.displayText
        layer.backgroundColor = config?.backgroundColor
    }

    public func highlightBackground() {
        let oldBackgroundColor = layer.backgroundColor
        layer.backgroundColor = highlightedBackgroundColor.cgColor

        UIView.animate(withDuration: 2.0) { [weak self] in
            self?.layer.backgroundColor = oldBackgroundColor
        }
    }
}

#if DEBUG
import SwiftUI

struct DepartureTimeBadge_Previews: PreviewProvider {
    private static let nowBadge: DepartureTimeBadge = {
        let badge = DepartureTimeBadge()
        badge.configure(.preview("NOW", color: .red))
        return badge
    }()

    private static let fiveMinutesBadge: DepartureTimeBadge = {
        let badge = DepartureTimeBadge()
        badge.configure(.preview("5m", color: .blue))
        return badge
    }()

    private static let ninetyNineMinutesBadge: DepartureTimeBadge = {
        let badge = DepartureTimeBadge()
        badge.configure(.preview("99m", color: .gray))
        return badge
    }()

    private static let nineNineNineChineseBadge: DepartureTimeBadge = {
        let badge = DepartureTimeBadge()
        badge.configure(.preview("999分", color: .blue))
        return badge
    }()

    // For fixing #354 -- TodayView “NOW” is ellipsized
    fileprivate static let constrainedFrameStack: UIStackView = {
        NSLayoutConstraint.activate([
            nowBadge.widthAnchor.constraint(equalToConstant: 48),
            fiveMinutesBadge.widthAnchor.constraint(equalToConstant: 48),
            ninetyNineMinutesBadge.widthAnchor.constraint(equalToConstant: 48),
            nineNineNineChineseBadge.widthAnchor.constraint(equalToConstant: 48)
        ])

        let stack = UIStackView.stack(axis: .horizontal, arrangedSubviews: [nowBadge, fiveMinutesBadge, ninetyNineMinutesBadge, nineNineNineChineseBadge])
        NSLayoutConstraint.activate([stack.heightAnchor.constraint(equalToConstant: 24)])
        return stack
    }()

    static var previews: some View {
        UIViewPreview {
            constrainedFrameStack
        }
        .previewLayout(.sizeThatFits)
        .padding()
    }
}

extension DepartureTimeBadge.Configuration {
    static func preview(_ text: String, color: UIColor) -> Self {
        return .init(accessibilityLabel: "", displayText: text, backgroundColor: color.cgColor)
    }
}
#endif
