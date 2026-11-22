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
    let followButton = UIButton(type: .system)

    let headerStack: UIStackView
    let textStack: UIStackView
    let badgeLabel = UILabel()
    private var badgeWidthConstraint: NSLayoutConstraint?
    private var badgeHeightConstraint: NSLayoutConstraint?
    private var textStackWidthConstraint: NSLayoutConstraint?

    let headsignLabel: UILabel
    let vehicleLabel: UILabel
    let countdownLabel = UILabel()
    let updatedLabel: UILabel

    private let routeShortName: String
    private let countdownTextString: String
    private let statusTextString: String
    private let statusColor: UIColor

    var badgeSize: CGFloat {
        badgeWidthConstraint?.constant ?? Layout.badgeSize
    }

    var headerStackAxis: NSLayoutConstraint.Axis {
        headerStack.axis
    }

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
        self.routeShortName = routeShortName
        self.countdownTextString = countdownText
        self.statusTextString = statusText
        self.statusColor = statusColor

        headsignLabel = Self.makeLabel(text: headsign, style: .subheadline, bold: true, numberOfLines: 0)
        self.vehicleLabel = Self.makeLabel(text: vehicleLabel, style: .caption1, color: .secondaryLabel, numberOfLines: 0)
        updatedLabel = Self.makeLabel(
            text: String(format: Self.positionUpdatedFormat, updatedText),
            style: .caption2,
            color: .tertiaryLabel,
            numberOfLines: 0
        )

        countdownLabel.numberOfLines = 0
        countdownLabel.adjustsFontForContentSizeCategory = true

        textStack = UIStackView.verticalStack(arrangedSubviews: [headsignLabel, self.vehicleLabel])

        // `.top` so a wrapping headsign grows downward from the badge rather than
        // dragging the badge to the vertical center of a three-line block.
        headerStack = UIStackView(arrangedSubviews: [badgeLabel, textStack])
        headerStack.alignment = .top
        headerStack.spacing = Layout.badgeToText

        super.init(frame: .zero)

        configureBadge(routeShortName: routeShortName, routeColor: routeColor)
        configureFollowButton()
        setupHierarchyAndConstraints()

        updateLayout(for: traitCollection)

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
            self.updateLayout(for: self.traitCollection)
        }

        // One VoiceOver element: reading five separate labels inside a callout is
        // worse than one sentence.
        isAccessibilityElement = true
        accessibilityLabel = [headsign, vehicleLabel, countdownText, statusText, updatedText]
            .joined(separator: ", ")
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupHierarchyAndConstraints() {
        textStackWidthConstraint = textStack.widthAnchor.constraint(equalTo: headerStack.widthAnchor)

        let rule = UIView()
        rule.backgroundColor = .separator
        let ruleHeight = rule.heightAnchor.constraint(equalToConstant: 1.0 / max(traitCollection.displayScale, 1.0))
        ruleHeight.isActive = true
        registerForTraitChanges([UITraitDisplayScale.self]) { (self: Self, _) in
            ruleHeight.constant = 1.0 / max(self.traitCollection.displayScale, 1.0)
        }

        let stack = UIStackView(arrangedSubviews: [headerStack, rule, countdownLabel, updatedLabel, followButton])
        stack.axis = .vertical
        stack.spacing = 10
        // The countdown and its freshness line are one thought; the button is not.
        stack.setCustomSpacing(2, after: countdownLabel)
        stack.setCustomSpacing(12, after: updatedLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let width = widthAnchor.constraint(equalToConstant: Layout.width)
        width.priority = UILayoutPriority(rawValue: 999)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            width
        ])
    }

    func updateLayout(for traitCollection: UITraitCollection) {
        let isAccessibility = traitCollection.preferredContentSizeCategory.isAccessibilityCategory

        if isAccessibility {
            headerStack.axis = .vertical
            headerStack.alignment = .leading
            textStackWidthConstraint?.isActive = true
        } else {
            textStackWidthConstraint?.isActive = false
            headerStack.axis = .horizontal
            headerStack.alignment = .top
        }

        let scaledBadgeSize = UIFontMetrics(forTextStyle: .body).scaledValue(for: Layout.badgeSize, compatibleWith: traitCollection)
        badgeWidthConstraint?.constant = scaledBadgeSize
        badgeHeightConstraint?.constant = scaledBadgeSize
        let cornerScale = scaledBadgeSize / Layout.badgeSize
        badgeLabel.layer.cornerRadius = Layout.badgeCornerRadius * cornerScale

        let baseFontSize: CGFloat = routeShortName.count <= 2 ? 17 : 13
        let baseFont = UIFont.systemFont(ofSize: baseFontSize, weight: .heavy)
        badgeLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: baseFont, compatibleWith: traitCollection)

        let headsignFont = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection)
        headsignLabel.font = headsignFont.bold
        vehicleLabel.font = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traitCollection)
        updatedLabel.font = UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traitCollection)

        countdownLabel.attributedText = Self.countdownText(
            countdown: countdownTextString,
            statusText: statusTextString,
            statusColor: statusColor,
            traitCollection: traitCollection
        )

        followButton.setNeedsUpdateConfiguration()

        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

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
        statusColor: UIColor,
        traitCollection: UITraitCollection? = nil
    ) -> NSAttributedString {
        let large = UIFont.preferredFont(forTextStyle: .title2, compatibleWith: traitCollection).bold
        let small = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection)

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
    private func configureBadge(routeShortName: String, routeColor: UIColor) {
        badgeLabel.text = routeShortName
        badgeLabel.textAlignment = .center
        badgeLabel.textColor = routeColor.badgeTextColor(preferring: nil, minimumRatio: 4.5)
        badgeLabel.backgroundColor = routeColor
        badgeLabel.adjustsFontSizeToFitWidth = true
        badgeLabel.minimumScaleFactor = 0.6
        badgeLabel.layer.cornerCurve = .continuous
        badgeLabel.clipsToBounds = true
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.isAccessibilityElement = false

        badgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let width = badgeLabel.widthAnchor.constraint(equalToConstant: Layout.badgeSize)
        let height = badgeLabel.heightAnchor.constraint(equalToConstant: Layout.badgeSize)
        badgeWidthConstraint = width
        badgeHeightConstraint = height
        NSLayoutConstraint.activate([width, height])
    }

    private func configureFollowButton() {
        var config = UIButton.Configuration.gray()
        config.title = OBALoc("vehicle_callout.follow_this_trip", value: "Follow this trip",
                              comment: "Button in the live-vehicle map callout that opens the trip screen.")
        config.titleLineBreakMode = .byWordWrapping
        config.image = UIImage(
            systemName: "chevron.forward",
            withConfiguration: UIImage.SymbolConfiguration(scale: .small)
        )
        config.imagePlacement = .trailing
        config.imagePadding = 4
        config.cornerStyle = .medium
        config.buttonSize = .medium
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { [weak self] incoming in
            var outgoing = incoming
            let traits = self?.traitCollection
            outgoing.font = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits).bold
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
        numberOfLines: Int = 0
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
