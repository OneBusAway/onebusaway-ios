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
    public var brand: UIColor = .black

    /// Light text color, used on dark backgrounds.
    public var lightText: UIColor = .white

    /// A gray text color, used on light backgrounds for de-emphasized text.
    public var secondaryLabel: UIColor = .gray

    /// The overlay color drawn on top of a `MapSnapshotter` image.
    public var mapSnapshotOverlayColor: UIColor = .clear

    /// Map annotation view stroke color.
    public var stopAnnotationStrokeColor: UIColor = .darkGray

    /// Map annotation view fill color
    public var stopAnnotationFillColor: UIColor = .gray

    /// The fill color for a directional arrow on a map annotation.
    public var stopArrowFillColor: UIColor = .red

    /// The color used to represent early departures.
    public var departureEarly: UIColor = .red

    /// The background color used to represent early departures on smaller user interfaces like a Today View extension.
    public var departureEarlyBackground: UIColor = .red

    /// The color used to represent late departures.
    public var departureLate: UIColor = .blue

    /// The background color used to represent late departures on smaller user interfaces like a Today View extension.
    public var departureLateBackground: UIColor = .blue

    /// The color used to represent on-time departures.
    public var departureOnTime: UIColor = .green

    /// The background color used to represent on time departures on smaller user interfaces like a Today View extension.
    public var departureOnTimeBackground: UIColor = .green

    /// The color used to represent departures with an unknown status. (i.e. We don't know if they are early/late/on-time.)
    public var departureUnknown: UIColor = .black

    /// The background color used to represent unknown departures on smaller user interfaces like a Today View extension.
    public var departureUnknownBackground: UIColor = .gray

    /// The color used to highlight changing properties in the UI.
    public var propertyChanged: UIColor = .yellow

    /// The background color of a grouped table.
    public var groupedTableBackground: UIColor = .white

    /// The background color of a row in a grouped table.
    public var groupedTableRowBackground: UIColor = .white

    /// The system background color. Works with Dark Mode in iOS 13 and above.
    public var systemBackground: UIColor = .white

    /// A gray color; useful for de-emphasized UI elements.
    public var gray: UIColor = .gray

    public var label: UIColor = .black

    public var separator: UIColor = .gray

    public var highlightedBackgroundColor: UIColor = .lightGray

    public var secondaryBackgroundColor: UIColor = .white

    public var systemFill: UIColor = .gray

    public var errorColor: UIColor = .red

    public var green: UIColor = .green

    public var blue: UIColor = .blue

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

        #if os(watchOS)
        departureEarly = .red
        departureEarlyBackground = .red
        #else
        departureEarly = .systemRed
        departureEarlyBackground = .systemRed
        #endif

        // Hex #129900 is better visibility for small text in light mode.
        // UIColor.systemGreen is better visibility for small text in dark mode.
        // See #506 and #508 for user feedback.
        #if os(watchOS)
        let departureOnTimeColor = UIColor.green
        #else
        let departureOnTimeColor = UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor.systemGreen
            } else {
                return UIColor(red: 0.07, green: 0.60, blue: 0.00, alpha: 1.00)
            }
        }
        #endif
        departureOnTime = departureOnTimeColor
        departureOnTimeBackground = departureOnTimeColor

        #if os(watchOS)
        departureUnknown = .white
        departureUnknownBackground = .gray
        #else
        departureUnknown = .label
        departureUnknownBackground = .systemGray
        #endif

        #if os(watchOS)
        departureLate = .blue
        departureLateBackground = .blue
        #else
        departureLate = .systemBlue
        departureLateBackground = .systemBlue
        #endif

        #if os(watchOS)
        gray = .gray
        green = .green
        blue = .blue
        #else
        gray = .systemGray
        green = .systemGreen
        blue = .systemBlue
        #endif

        #if os(watchOS)
        groupedTableBackground = .black
        groupedTableRowBackground = .darkGray
        systemBackground = .black
        label = .white
        secondaryLabel = .lightGray
        separator = .darkGray
        highlightedBackgroundColor = .darkGray
        secondaryBackgroundColor = .black
        #else
        groupedTableBackground = .systemGroupedBackground
        groupedTableRowBackground = .white
        systemBackground = .systemBackground
        label = .label
        secondaryLabel = .secondaryLabel
        separator = .separator
        highlightedBackgroundColor = .systemFill
        secondaryBackgroundColor = .secondarySystemBackground
        #endif

        #if os(watchOS)
        propertyChanged = .yellow
        #else
        propertyChanged = .systemYellow
        #endif

        #if os(watchOS)
        stopAnnotationFillColor = .gray
        #else
        stopAnnotationFillColor = .systemGray6
        #endif
        stopAnnotationStrokeColor = .darkGray

        #if os(watchOS)
        stopArrowFillColor = .red
        #else
        stopArrowFillColor = .systemRed
        #endif

        #if os(watchOS)
        systemFill = .darkGray
        #else
        systemFill = .systemFill
        #endif
        lightText = .white

        #if os(watchOS)
        errorColor = .red
        #else
        errorColor = .systemRed
        #endif
    }
}
