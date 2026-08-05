//
//  VehicleCalloutView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import UIKit

/// The callout shown when a rider taps a live vehicle on the map.
///
/// Built as a plain `UIView` rather than a hosted SwiftUI view: a MapKit
/// `detailCalloutAccessoryView` needs a concrete view with a sensible intrinsic
/// size, and hosting SwiftUI here would require a child view controller for no
/// benefit.
///
/// Layout follows the design's vehicle card: route badge beside the headsign,
/// a rule, then the countdown line and the follow button. The headsign wraps
/// rather than truncating — the design truncates it, but a headsign is the one
/// piece of text here a rider actually has to read.
final class VehicleCalloutView: UIView {

    private enum Layout {
        /// MapKit callouts have no intrinsic width. Wide enough for the badge
        /// plus a two-word headsign fragment before it wraps.
        static let width: CGFloat = 240
        static let badgeSize: CGFloat = 32
        static let badgeCornerRadius: CGFloat = 9
        static let badgeToText: CGFloat = 8
    }

    private let onFollow: () -> Void
    private let followButton = UIButton(type: .system)

    init(
        routeShortName: String,
        headsign: String,
        vehicleLabel: String,
        countdownText: String,
        statusText: String,
        statusColor: UIColor,
        updatedText: String,
        routeColor: UIColor,
        onFollow: @escaping () -> Void
    ) {
        self.onFollow = onFollow
        super.init(frame: .zero)

        let headsignLabel = Self.makeLabel(text: headsign, style: .subheadline, bold: true, numberOfLines: 3)
        let vehicle = Self.makeLabel(text: vehicleLabel, style: .caption1, color: .secondaryLabel)
        let updated = Self.makeLabel(
            text: String(format: Self.positionUpdatedFormat, updatedText),
            style: .caption2,
            color: .tertiaryLabel
        )

        let countdown = UILabel()
        countdown.numberOfLines = 0
        countdown.adjustsFontForContentSizeCategory = true
        countdown.attributedText = Self.countdownText(
            countdown: countdownText,
            statusText: statusText,
            statusColor: statusColor
        )

        configureFollowButton()

        // `.top` so a wrapping headsign grows downward from the badge rather than
        // dragging the badge to the vertical center of a three-line block.
        let header = UIStackView(arrangedSubviews: [
            Self.makeBadge(routeShortName: routeShortName, routeColor: routeColor),
            UIStackView.verticalStack(arrangedSubviews: [headsignLabel, vehicle])
        ])
        header.axis = .horizontal
        header.alignment = .top
        header.spacing = Layout.badgeToText

        let rule = UIView()
        rule.backgroundColor = .separator
        rule.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true

        let stack = UIStackView(arrangedSubviews: [header, rule, countdown, updated, followButton])
        stack.axis = .vertical
        stack.spacing = 10
        // The countdown and its freshness line are one thought; the button is not.
        stack.setCustomSpacing(2, after: countdown)
        stack.setCustomSpacing(12, after: updated)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: Layout.width)
        ])

        // One VoiceOver element: reading five separate labels inside a callout is
        // worse than one sentence.
        isAccessibilityElement = true
        accessibilityLabel = [headsign, vehicleLabel, countdownText, statusText, updatedText]
            .joined(separator: ", ")
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Strings

    private static let positionUpdatedFormat = OBALoc(
        "vehicle_callout.position_updated_fmt",
        value: "Position updated %@",
        comment: "Freshness line in the live-vehicle map callout. %@ is a relative time, e.g. '12s ago'."
    )

    private static let toThisStop = OBALoc(
        "vehicle_callout.to_this_stop",
        value: "to this stop",
        comment: "Qualifies the countdown in the live-vehicle map callout, as in '1m to this stop'."
    )

    // MARK: - Subview builders

    /// The countdown line — "1m to this stop · 1 min late" — as one attributed
    /// string rather than a horizontal stack of labels.
    ///
    /// A stack sets the pieces at fixed positions, which is what pushed the
    /// adherence text to the far edge with a gap in the middle. One string lets
    /// the phrase read as a sentence and wrap as a unit; the mixed font sizes
    /// still share a baseline.
    private static func countdownText(
        countdown: String,
        statusText: String,
        statusColor: UIColor
    ) -> NSAttributedString {
        let large = UIFont.preferredFont(forTextStyle: .title2).bold
        let small = UIFont.preferredFont(forTextStyle: .subheadline)

        let text = NSMutableAttributedString(
            string: countdown,
            attributes: [.font: large, .foregroundColor: statusColor]
        )
        text.append(NSAttributedString(
            string: " \(toThisStop)",
            attributes: [.font: small, .foregroundColor: UIColor.secondaryLabel]
        ))

        guard !statusText.isEmpty else { return text }

        text.append(NSAttributedString(
            string: " · ",
            attributes: [.font: small, .foregroundColor: UIColor.tertiaryLabel]
        ))
        text.append(NSAttributedString(
            string: statusText,
            attributes: [.font: small, .foregroundColor: statusColor]
        ))
        return text
    }

    /// The rounded-square route badge. A hand-rolled UIKit twin of the SwiftUI
    /// `RouteBadgeView` — hosting that one inside a `detailCalloutAccessoryView`
    /// would mean a child view controller for a 32pt square. The text color comes
    /// from the same WCAG helper, so the two cannot disagree about legibility.
    private static func makeBadge(routeShortName: String, routeColor: UIColor) -> UIView {
        let badge = UILabel()
        badge.text = routeShortName
        badge.textAlignment = .center
        badge.font = .systemFont(ofSize: routeShortName.count <= 2 ? 17 : 13, weight: .heavy)
        badge.textColor = routeColor.badgeTextColor(preferring: nil, minimumRatio: 4.5)
        badge.backgroundColor = routeColor
        badge.adjustsFontSizeToFitWidth = true
        badge.minimumScaleFactor = 0.6
        badge.layer.cornerRadius = Layout.badgeCornerRadius
        badge.layer.cornerCurve = .continuous
        badge.clipsToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: Layout.badgeSize),
            badge.heightAnchor.constraint(equalToConstant: Layout.badgeSize)
        ])
        // The route name is already in the callout's combined accessibility label.
        badge.isAccessibilityElement = false
        return badge
    }

    private func configureFollowButton() {
        var config = UIButton.Configuration.gray()
        config.title = OBALoc("vehicle_callout.follow_this_trip", value: "Follow this trip",
                              comment: "Button in the live-vehicle map callout that opens the trip screen.")
        config.image = UIImage(
            systemName: "chevron.right",
            withConfiguration: UIImage.SymbolConfiguration(scale: .small)
        )
        config.imagePlacement = .trailing
        config.imagePadding = 4
        config.cornerStyle = .medium
        config.buttonSize = .medium
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.preferredFont(forTextStyle: .subheadline).bold
            return outgoing
        }
        followButton.configuration = config
        followButton.addTarget(self, action: #selector(followTapped), for: .touchUpInside)
    }

    private static func makeLabel(
        text: String,
        style: UIFont.TextStyle,
        bold: Bool = false,
        color: UIColor = .label,
        numberOfLines: Int = 1
    ) -> UILabel {
        let label = UILabel()
        label.text = text
        let font = UIFont.preferredFont(forTextStyle: style)
        label.font = bold ? font.bold : font
        label.textColor = color
        label.numberOfLines = numberOfLines
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    @objc private func followTapped() {
        onFollow()
    }

    /// Test seam — exercises the same path as a real tap.
    func simulateFollowTap() {
        followTapped()
    }

    override func accessibilityActivate() -> Bool {
        followTapped()
        return true
    }
}
