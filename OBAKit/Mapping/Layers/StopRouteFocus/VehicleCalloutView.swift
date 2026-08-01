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
final class VehicleCalloutView: UIView {

    private let onFollow: () -> Void
    private let followButton = UIButton(type: .system)

    init(
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

        let headsignLabel = Self.makeLabel(text: headsign, style: .subheadline, bold: true, numberOfLines: 2)
        let vehicle = Self.makeLabel(text: vehicleLabel, style: .caption1, color: .secondaryLabel)
        let countdown = Self.makeLabel(text: countdownText, style: .title2, bold: true, color: statusColor)
        let status = Self.makeLabel(text: statusText, style: .caption1, color: statusColor)
        let updated = Self.makeLabel(text: updatedText, style: .caption2, color: .tertiaryLabel)

        var config = UIButton.Configuration.gray()
        config.title = OBALoc("vehicle_callout.follow_this_trip", value: "Follow this trip",
                              comment: "Button in the live-vehicle map callout that opens the trip screen.")
        config.image = UIImage(systemName: "chevron.right")
        config.imagePlacement = .trailing
        config.imagePadding = 6
        config.cornerStyle = .medium
        followButton.configuration = config
        followButton.addTarget(self, action: #selector(followTapped), for: .touchUpInside)

        let statusRow = UIStackView(arrangedSubviews: [countdown, status])
        statusRow.axis = .horizontal
        statusRow.alignment = .firstBaseline
        statusRow.spacing = 6

        let stack = UIStackView(arrangedSubviews: [headsignLabel, vehicle, statusRow, updated, followButton])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            // MapKit callouts have no intrinsic width; without this the content
            // collapses to the widest single word.
            widthAnchor.constraint(equalToConstant: 214)
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

    /// Factored out of `init` purely to keep it under SwiftLint's function-body-length
    /// limit — the five callout labels differ only in style, color, and line count.
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
