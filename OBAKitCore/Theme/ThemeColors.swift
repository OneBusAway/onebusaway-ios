//
//  ThemeColors.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

// Every stored property is an immutable UIColor (Sendable); @unchecked only because NSObject is not Sendable.
public final class ThemeColors: NSObject, @unchecked Sendable {

    /// Primary theme color/brand color.
    public let brand: UIColor

    /// The darker brand shade for links, focus and primary buttons (`#486621`,
    /// `#5B802A` in dark mode, unless the app bundle names a `brandAccent` colour).
    public let brandAccent: UIColor

    /// The docked bar's background when the rider is outside every zone.
    public let onDemandOutside: UIColor

    /// The weight of "Open" in on-demand status lines.
    public let onDemandOpenGreen: UIColor

    /// Light text color, used on dark backgrounds.
    public let lightText: UIColor

    /// A gray text color, used on light backgrounds for de-emphasized text.
    public let secondaryLabel: UIColor

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
        self.init(bundle: Bundle.main)
    }

    public convenience init(bundle: Bundle) {
        self.init(brand: Palette.brand(in: bundle), brandAccent: Palette.brandAccent(in: bundle), palette: .platformDefault)
    }

    #if !os(watchOS)
    // watchOS has neither `UITraitCollection` nor `UIColor(named:in:compatibleWith:)`.
    // This and `Palette.system` below are the only platform conditionals in the
    // theme; keep it that way.
    public convenience init(bundle: Bundle, traitCollection: UITraitCollection?) {
        self.init(
            brand: UIColor(named: "brand", in: bundle, compatibleWith: traitCollection),
            brandAccent: UIColor(named: "brandAccent", in: bundle, compatibleWith: traitCollection),
            palette: .system
        )
    }
    #endif

    private init(brand: UIColor?, brandAccent: UIColor?, palette: Palette) {
        self.brand = brand ?? UIColor(red: 0.471, green: 0.667, blue: 0.212, alpha: 1.0)  // fallback for swiftui previews
        self.brandAccent = brandAccent ?? palette.brandAccent
        onDemandOutside = UIColor(red: 0x63 / 255.0, green: 0x63 / 255.0, blue: 0x66 / 255.0, alpha: 1.0)
        onDemandOpenGreen = UIColor(red: 0x24 / 255.0, green: 0x8a / 255.0, blue: 0x3d / 255.0, alpha: 1.0)

        mapSnapshotOverlayColor = UIColor(white: 0.0, alpha: 0.4)

        departureEarly = palette.red
        departureEarlyBackground = palette.red

        departureOnTime = palette.onTime
        departureOnTimeBackground = palette.onTime

        departureUnknown = palette.label
        departureUnknownBackground = palette.gray

        departureLate = palette.blue
        departureLateBackground = palette.blue

        gray = palette.gray
        green = palette.green
        blue = palette.blue
        groupedTableBackground = palette.groupedBackground
        groupedTableRowBackground = .white
        systemBackground = palette.background
        label = palette.label
        secondaryLabel = palette.secondaryLabel
        separator = palette.separator
        highlightedBackgroundColor = palette.fill
        secondaryBackgroundColor = palette.secondaryBackground
        propertyChanged = palette.yellow

        stopAnnotationFillColor = palette.gray6
        stopAnnotationStrokeColor = .darkGray
        stopArrowFillColor = palette.red
        systemFill = palette.fill
        lightText = .white
        errorColor = palette.red
    }

    /// The system-provided colors the theme is built from.
    ///
    /// iOS uses the semantic, light/dark-adaptive `UIColor`s. watchOS's
    /// `UIColor` has none of them, so the watch gets fixed values — Apple's
    /// published dark-appearance values, since a watch face is always dark.
    struct Palette {
        let red: UIColor
        let blue: UIColor
        let green: UIColor
        let onTime: UIColor
        let gray: UIColor
        let yellow: UIColor
        let label: UIColor
        let secondaryLabel: UIColor
        let separator: UIColor
        let fill: UIColor
        let background: UIColor
        let secondaryBackground: UIColor
        let groupedBackground: UIColor
        let gray6: UIColor
        let brandAccent: UIColor

        static let lightBrandAccent = UIColor(red: 0x48 / 255.0, green: 0x66 / 255.0, blue: 0x21 / 255.0, alpha: 1.0)
        /// Lighter, so accent text keeps 4.5:1 on a black card; still dark
        /// enough that a pill's white label keeps 4.5:1 on it.
        static let darkBrandAccent = UIColor(red: 0x5b / 255.0, green: 0x80 / 255.0, blue: 0x2a / 255.0, alpha: 1.0)

        /// Defined on every platform — not just watchOS — so the iOS-hosted
        /// test suite can check it.
        static let watch = Palette(
            red: UIColor(red: 1.000, green: 0.271, blue: 0.227, alpha: 1),
            blue: UIColor(red: 0.039, green: 0.518, blue: 1.000, alpha: 1),
            green: UIColor(red: 0.188, green: 0.820, blue: 0.345, alpha: 1),
            onTime: UIColor(red: 0.188, green: 0.820, blue: 0.345, alpha: 1),
            gray: UIColor(red: 0.557, green: 0.557, blue: 0.576, alpha: 1),
            yellow: UIColor(red: 1.000, green: 0.839, blue: 0.039, alpha: 1),
            label: .white,
            secondaryLabel: UIColor(red: 0.922, green: 0.922, blue: 0.961, alpha: 0.6),
            separator: UIColor(red: 0.329, green: 0.329, blue: 0.345, alpha: 0.6),
            fill: UIColor(red: 0.471, green: 0.471, blue: 0.502, alpha: 0.36),
            background: .black,
            secondaryBackground: UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1),
            groupedBackground: .black,
            gray6: UIColor(red: 0.110, green: 0.110, blue: 0.118, alpha: 1),
            brandAccent: darkBrandAccent
        )

        #if os(watchOS)
        static let platformDefault = watch

        static func brand(in bundle: Bundle) -> UIColor? {
            // watchOS can only look a named color up in the main bundle.
            UIColor(named: "brand")
        }

        static func brandAccent(in bundle: Bundle) -> UIColor? {
            UIColor(named: "brandAccent")
        }
        #else
        static let platformDefault = system

        static func brand(in bundle: Bundle) -> UIColor? {
            UIColor(named: "brand", in: bundle, compatibleWith: nil)
        }

        static func brandAccent(in bundle: Bundle) -> UIColor? {
            UIColor(named: "brandAccent", in: bundle, compatibleWith: nil)
        }

        static let system = Palette(
            red: .systemRed,
            blue: .systemBlue,
            green: .systemGreen,
            // Hex #007300 (red: 0.00, green: 0.45, blue: 0.00) has a 6.1:1 contrast ratio against white in
            // light mode, clearing the WCAG AA minimum of 4.5:1 for normal-size text.
            // UIColor.systemGreen is better visibility for small text in dark mode.
            // See #506, #508, and #599 for user feedback.
            onTime: UIColor { traitCollection in
                if traitCollection.userInterfaceStyle == .dark {
                    return UIColor.systemGreen
                } else {
                    return UIColor(red: 0.00, green: 0.45, blue: 0.00, alpha: 1.00)
                }
            },
            gray: .systemGray,
            yellow: .systemYellow,
            label: .label,
            secondaryLabel: .secondaryLabel,
            separator: .separator,
            fill: .systemFill,
            background: .systemBackground,
            secondaryBackground: .secondarySystemBackground,
            groupedBackground: .systemGroupedBackground,
            gray6: .systemGray6,
            brandAccent: UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? darkBrandAccent : lightBrandAccent
            }
        )
        #endif
    }
}
