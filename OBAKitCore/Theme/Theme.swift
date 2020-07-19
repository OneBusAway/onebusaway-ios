//
//  Theme.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

// swiftlint:disable function_body_length

public class ThemeMetrics: NSObject {

    public static let accessibilityPadding: CGFloat = 16.0

    public static let padding: CGFloat = 8.0

    public static let compactPadding: CGFloat = 4.0

    public static let ultraCompactPadding: CGFloat = 2.0

    public static let controllerMargin: CGFloat = 20.0

    public static let defaultMapAnnotationSize: CGFloat = 48.0

    public static let cornerRadius: CGFloat = 8.0

    public static let compactCornerRadius: CGFloat = 4.0

    public static let buttonContentPadding: CGFloat = 6.0

    public static let floatingPanelTopInset: CGFloat = 7.0

    public static let collectionViewLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: padding, bottom: 0, trailing: padding)
}

public class ThemeColors: NSObject {

    /// Primary theme color/brand color.
    public let brand: UIColor

    /// Light text color, used on dark backgrounds.
    public let lightText: UIColor

    /// A gray text color, used on light backgrounds for de-emphasized text.
    public let secondaryLabel: UIColor

    /// A dark gray text color, used on maps.
    public let mapText: UIColor

    /// The overlay color drawn on top of a `MapSnapshotter` image.
    public let mapSnapshotOverlayColor: UIColor

    /// Map annotation view stroke color.
    public let stopAnnotationStrokeColor: UIColor

    /// Map annotation view fill color
    public let stopAnnotationFillColor: UIColor

    /// The fill color for a directional arrow on a map annotation.
    public let stopArrowFillColor: UIColor

    /// The color used to represent early departures.
    public let departureEarly: UIColor

    /// The background color used to represent early departures on smaller user interfaces like a Today View extension.
    public let departureEarlyBackground: UIColor

    /// The color used to represent late departures.
    public let departureLate: UIColor

    /// The background color used to represent late departures on smaller user interfaces like a Today View extension.
    public let departureLateBackground: UIColor

    /// The color used to represent on-time departures.
    public let departureOnTime: UIColor

    /// The background color used to represent on time departures on smaller user interfaces like a Today View extension.
    public let departureOnTimeBackground: UIColor

    /// The color used to represent departures with an unknown status. (i.e. We don't know if they are early/late/on-time.)
    public let departureUnknown: UIColor

    /// The background color used to represent unknown departures on smaller user interfaces like a Today View extension.
    public let departureUnknownBackground: UIColor

    /// The color used to highlight changing properties in the UI.
    public let propertyChanged: UIColor

    /// The background color of a grouped table.
    public let groupedTableBackground: UIColor

    /// The background color of a row in a grouped table.
    public let groupedTableRowBackground: UIColor

    /// The system background color. Works with Dark Mode in iOS 13 and above.
    public let systemBackground: UIColor

    /// A gray color; useful for de-emphasized UI elements.
    public let gray: UIColor

    public let label: UIColor

    public let separator: UIColor

    public let highlightedBackgroundColor: UIColor

    public let secondaryBackgroundColor: UIColor

    public let systemFill: UIColor

    public let errorColor: UIColor

    public let green: UIColor

    public let blue: UIColor

    public static let shared = ThemeColors()

    public override convenience init() {
        self.init(bundle: Bundle.main, traitCollection: nil)
    }

    public init(bundle: Bundle, traitCollection: UITraitCollection?) {
        brand = UIColor(named: "brand", in: bundle, compatibleWith: traitCollection)!
        mapSnapshotOverlayColor = UIColor(white: 0.0, alpha: 0.4)

        if #available(iOS 13, *) {
            departureEarly = .systemRed
            departureEarlyBackground = .systemRed

            departureOnTime = .systemGreen
            departureOnTimeBackground = .systemGreen

            departureUnknown = .label
            departureUnknownBackground = .systemGray

            departureLate = .systemBlue
            departureLateBackground = .systemBlue

            gray = .systemGray
            green = .systemGreen
            blue = .systemBlue
            groupedTableBackground = .systemGroupedBackground
            groupedTableRowBackground = .white
            systemBackground = .systemBackground
            mapText = .label
            label = .label
            secondaryLabel = .secondaryLabel
            separator = .separator
            highlightedBackgroundColor = .systemFill
            secondaryBackgroundColor = .secondarySystemBackground
            propertyChanged = .systemYellow

            stopAnnotationFillColor = .systemBackground
            stopAnnotationStrokeColor = .label
            stopArrowFillColor = .systemRed
            systemFill = .systemFill
            lightText = .white
            errorColor = .systemRed
        }
        else {
            departureEarly = UIColor(hex: "fc3f3b")!
            departureEarlyBackground = departureEarly

            departureOnTime = UIColor(hex: "16771a")!
            departureOnTimeBackground = departureOnTime

            departureUnknown = .black
            departureUnknownBackground = .darkGray

            departureLate = UIColor(hex: "0082f8")!
            departureLateBackground = departureLate

            gray = .gray
            green = .green
            blue = .blue
            groupedTableBackground = .groupTableViewBackground
            groupedTableRowBackground = .white
            systemBackground = .white
            mapText = UIColor(r: 42, g: 44, b: 47)
            label = .black
            secondaryLabel = .darkGray
            separator = UIColor(red: 200 / 255.0, green: 199 / 255.0, blue: 204 / 255.0, alpha: 1)
            highlightedBackgroundColor = UIColor(white: 0.9, alpha: 1)
            secondaryBackgroundColor = UIColor(white: 0.9, alpha: 1)
            propertyChanged = UIColor(r: 255, g: 255, b: 128)

            stopAnnotationFillColor = .white
            stopAnnotationStrokeColor = .black
            stopArrowFillColor = .red
            systemFill = UIColor(white: 0.9, alpha: 1)
            lightText = .white
            errorColor = .red
        }
    }
}
