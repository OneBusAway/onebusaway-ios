//
//  Theme.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

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

    public static let stopAnnotationIconInset: CGFloat = 6.0

    public static let stopAnnotationCornerRadius: CGFloat = 4.0
}

public class ThemeColors: NSObject {

    /// Primary theme color/brand color.
    public private(set) var brand: UIColor = .black

    /// Light text color, used on dark backgrounds.
    public private(set) var lightText: UIColor = .white

    /// A gray text color, used on light backgrounds for de-emphasized text.
    public private(set) var secondaryLabel: UIColor = .gray

    /// The overlay color drawn on top of a `MapSnapshotter` image.
    public private(set) var mapSnapshotOverlayColor: UIColor = .clear

    /// Map annotation view stroke color.
    public private(set) var stopAnnotationStrokeColor: UIColor = .darkGray

    /// Map annotation view fill color
    public private(set) var stopAnnotationFillColor: UIColor = .gray

    /// The fill color for a directional arrow on a map annotation.
    public private(set) var stopArrowFillColor: UIColor = .red

    /// The color used to represent early departures.
    public private(set) var departureEarly: UIColor = .red

    /// The background color used to represent early departures on smaller user interfaces like a Today View extension.
    public private(set) var departureEarlyBackground: UIColor = .red

    /// The color used to represent late departures.
    public private(set) var departureLate: UIColor = .blue

    /// The background color used to represent late departures on smaller user interfaces like a Today View extension.
    public private(set) var departureLateBackground: UIColor = .blue

    /// The color used to represent on-time departures.
    public private(set) var departureOnTime: UIColor = .green

    /// The background color used to represent on time departures on smaller user interfaces like a Today View extension.
    public private(set) var departureOnTimeBackground: UIColor = .green

    /// The color used to represent departures with an unknown status. (i.e. We don't know if they are early/late/on-time.)
    public private(set) var departureUnknown: UIColor = .black

    /// The background color used to represent unknown departures on smaller user interfaces like a Today View extension.
    public private(set) var departureUnknownBackground: UIColor = .gray

    /// The color used to highlight changing properties in the UI.
    public private(set) var propertyChanged: UIColor = .yellow

    /// The background color of a grouped table.
    public private(set) var groupedTableBackground: UIColor = .white

    /// The background color of a row in a grouped table.
    public private(set) var groupedTableRowBackground: UIColor = .white

    /// The system background color. Works with Dark Mode in iOS 13 and above.
    public private(set) var systemBackground: UIColor = .white

    /// A gray color; useful for de-emphasized UI elements.
    public private(set) var gray: UIColor = .gray

    public private(set) var label: UIColor = .black

    public private(set) var separator: UIColor = .gray

    public private(set) var highlightedBackgroundColor: UIColor = .lightGray

    public private(set) var secondaryBackgroundColor: UIColor = .white

    public private(set) var systemFill: UIColor = .gray

    public private(set) var errorColor: UIColor = .red

    public private(set) var green: UIColor = .green

    public private(set) var blue: UIColor = .blue

    public static let shared = ThemeColors()

    public override convenience init() {
        #if os(watchOS)
        self.init(bundle: Bundle.main)
        #else
        self.init(bundle: Bundle.main, traitCollection: nil)
        #endif
    }

    #if !os(watchOS)
    public init(bundle: Bundle, traitCollection: UITraitCollection?) {
        super.init()
        brand = UIColor(named: "brand", in: bundle, compatibleWith: traitCollection) ??
            UIColor(red: 0.471, green: 0.667, blue: 0.212, alpha: 1.0)  // fallback for swiftui previews
        commonInit(bundle: bundle)
    }
    #else
    public init(bundle: Bundle) {
        super.init()
        brand = UIColor(named: "brand") ??
            UIColor(red: 0.471, green: 0.667, blue: 0.212, alpha: 1.0)  // fallback for swiftui previews
        commonInit(bundle: bundle)
    }
    #endif

    private func commonInit(bundle: Bundle) {
        mapSnapshotOverlayColor = UIColor(white: 0.0, alpha: 0.4)
        stopAnnotationStrokeColor = .darkGray
        lightText = .white

        #if os(watchOS)
        departureEarly = .red
        departureEarlyBackground = .red

        departureOnTime = .green
        departureOnTimeBackground = .green

        departureUnknown = .white
        departureUnknownBackground = .gray

        departureLate = .blue
        departureLateBackground = .blue

        gray = .gray
        green = .green
        blue = .blue

        groupedTableBackground = .black
        groupedTableRowBackground = .darkGray
        systemBackground = .black
        label = .white
        secondaryLabel = .lightGray
        separator = .darkGray
        highlightedBackgroundColor = .darkGray
        secondaryBackgroundColor = .black

        propertyChanged = .yellow
        stopAnnotationFillColor = .gray
        stopArrowFillColor = .red
        systemFill = .darkGray
        errorColor = .red
        #else
        departureEarly = .systemRed
        departureEarlyBackground = .systemRed

        // Hex #129900 is better visibility for small text in light mode.
        // UIColor.systemGreen is better visibility for small text in dark mode.
        // See #506 and #508 for user feedback.
        let departureOnTimeColor = UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor.systemGreen
            } else {
                return UIColor(red: 0.07, green: 0.60, blue: 0.00, alpha: 1.00)
            }
        }
        departureOnTime = departureOnTimeColor
        departureOnTimeBackground = departureOnTimeColor

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
        label = .label
        secondaryLabel = .secondaryLabel
        separator = .separator
        highlightedBackgroundColor = .systemFill
        secondaryBackgroundColor = .secondarySystemBackground

        propertyChanged = .systemYellow
        stopAnnotationFillColor = .systemGray6
        stopArrowFillColor = .systemRed
        systemFill = .systemFill
        errorColor = .systemRed
        #endif
    }
}
