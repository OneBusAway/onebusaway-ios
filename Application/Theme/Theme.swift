//
//  Theme.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/25/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit

public class Theme: NSObject {
    public let colors: ThemeColors
    public let fonts: ThemeFonts
    public let metrics: ThemeMetrics
    public let behaviors: ThemeBehaviors

    public init(bundle: Bundle?, traitCollection: UITraitCollection?) {
        colors = ThemeColors(bundle: bundle ?? Bundle(for: Theme.self), traitCollection: traitCollection)
        fonts = ThemeFonts()
        metrics = ThemeMetrics()
        behaviors = ThemeBehaviors()
    }
}

public class ThemeMetrics: NSObject {

    public static let padding: CGFloat = 8.0

    public static let compactPadding: CGFloat = 4.0

    public static let ultraCompactPadding: CGFloat = 2.0

    public static let controllerMargin: CGFloat = 20.0

    public static let defaultMapAnnotationSize: CGFloat = 54.0

    public static let cornerRadius: CGFloat = 8.0

    public static let tableHeaderTopPadding: CGFloat = 20.0

    public static let compactTopBottomEdgeInsets = NSDirectionalEdgeInsets(top: 4.0, leading: 0, bottom: -4.0, trailing: 0)

    public static let collectionViewLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: padding, bottom: 0, trailing: padding)
}

public class ThemeColors: NSObject {

    /// Primary theme color.
    public let primary: UIColor

    /// Dark variant of the primary theme color.
    public let dark: UIColor

    /// Light variant of the primary theme color.
    public let light: UIColor

    /// Light text color, used on dark backgrounds.
    public let lightText: UIColor

    /// A gray text color, used on light backgrounds for de-emphasized text.
    public let subduedText: UIColor

    /// A dark gray text color, used on maps.
    public let mapText: UIColor

    /// Tint color for map annotation views representing stops.
    public let stopAnnotationIcon: UIColor

    /// The color used to represent early departures.
    public let departureEarly: UIColor

    /// The color used to represent late departures.
    public let departureLate: UIColor

    /// The color used to represent on-time departures.
    public let departureOnTime: UIColor

    /// The color used to represent departures with an unknown status. (i.e. We don't know if they are early/late/on-time.)
    public let departureUnknown: UIColor

    /// The color used to highlight changing properties in the UI.
    public let propertyChanged: UIColor

    /// The background color of a grouped table.
    public let groupedTableBackground: UIColor

    /// The background color of a row in a grouped table.
    public let groupedTableRowBackground: UIColor

    /// The system background color. Works with Dark Mode in iOS 13 and above.
    public let systemBackground: UIColor

    public override convenience init() {
        self.init(bundle: Bundle(for: type(of: self)), traitCollection: nil)
    }

    public init(bundle: Bundle, traitCollection: UITraitCollection?) {
        primary = UIColor(named: "primary", in: bundle, compatibleWith: traitCollection)!
        dark = UIColor(named: "dark", in: bundle, compatibleWith: traitCollection)!
        light = UIColor(named: "light", in: bundle, compatibleWith: traitCollection)!
        lightText = UIColor(named: "lightText", in: bundle, compatibleWith: traitCollection)!
        subduedText = UIColor(named: "subduedText", in: bundle, compatibleWith: traitCollection)!
        mapText = UIColor(named: "mapTextColor", in: bundle, compatibleWith: traitCollection)!
        stopAnnotationIcon = UIColor(named: "stopAnnotationIconColor", in: bundle, compatibleWith: traitCollection)!
        departureEarly = UIColor(named: "departureEarly", in: bundle, compatibleWith: traitCollection)!
        departureLate = UIColor(named: "departureLate", in: bundle, compatibleWith: traitCollection)!
        departureOnTime = UIColor(named: "departureOnTime", in: bundle, compatibleWith: traitCollection)!
        departureUnknown = UIColor(named: "departureUnknown", in: bundle, compatibleWith: traitCollection)!
        propertyChanged = UIColor(named: "propertyChanged", in: bundle, compatibleWith: traitCollection)!

        if #available(iOS 13, *) {
            groupedTableBackground = .systemGroupedBackground
            groupedTableRowBackground = .white
            systemBackground = .systemBackground
        }
        else {
            groupedTableBackground = .groupTableViewBackground
            groupedTableRowBackground = .white
            systemBackground = .white
        }
    }
}

public class ThemeFonts: NSObject {

    // MARK: - Fonts

    public lazy var largeTitle = ThemeFonts.boldFont(textStyle: UIFont.TextStyle.title1)
    public lazy var title = ThemeFonts.boldFont(textStyle: UIFont.TextStyle.title2)

    public lazy var body = ThemeFonts.font(textStyle: UIFont.TextStyle.body)
    public lazy var boldBody = ThemeFonts.boldFont(textStyle: UIFont.TextStyle.body)

    public lazy var footnote = ThemeFonts.font(textStyle: UIFont.TextStyle.footnote)
    public lazy var boldFootnote = ThemeFonts.boldFont(textStyle: UIFont.TextStyle.footnote)

    public lazy var mapAnnotation: UIFont = {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: UIFont.TextStyle.footnote)
        return UIFont.systemFont(ofSize: descriptor.pointSize - 2.0, weight: .black)
    }()

    // MARK: - Internal

    private static let maxFontSize: CGFloat = 32.0

    private class func font(textStyle: UIFont.TextStyle, pointSize: CGFloat? = nil) -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle)
        let size = pointSize ?? min(descriptor.pointSize, maxFontSize)
        return UIFont(descriptor: descriptor, size: size)
    }

    private class func boldFont(textStyle: UIFont.TextStyle, pointSize: CGFloat? = nil) -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle).withSymbolicTraits(.traitBold)!
        let size = pointSize ?? min(descriptor.pointSize, maxFontSize)
        return UIFont(descriptor: descriptor, size: size)
    }
}

public class ThemeBehaviors: NSObject {
    /// When true, the app will use floating panels in lieu of a tabbed UI.
    public let useFloatingPanelNavigation = false

    /// When true, tapping on a map annotation will show a callout.
    ///
    /// - Note: This behavior may be overriden by other features, like VoiceOver.
    ///         Because of how annotation selection works when VoiceOver is on,
    ///         it doesn't make any sense to display map callouts in that mode.
    public let mapShowsCallouts = true
}
