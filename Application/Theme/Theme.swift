//
//  Theme.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/25/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit

@objc(OBATheme)
public class Theme: NSObject {
    public let colors: ThemeColors
    public let fonts: ThemeFonts
    public let metrics: ThemeMetrics

    public init(bundle: Bundle?, traitCollection: UITraitCollection?) {
        colors = ThemeColors(bundle: bundle ?? Bundle(for: Theme.self), traitCollection: traitCollection)
        fonts = ThemeFonts()
        metrics = ThemeMetrics()
    }
}

@objc(OBAThemeMetrics)
public class ThemeMetrics: NSObject {

    public let padding: CGFloat = 10.0

    public let controllerMargin: CGFloat = 20.0
}

@objc(OBAThemeColors)
public class ThemeColors: NSObject {

    /// Primary theme color.
    public let primary: UIColor

    /// Dark variant of the primary theme color.
    public let dark: UIColor

    /// Light variant of the primary theme color.
    public let light: UIColor

    /// Light text color, used on dark backgrounds.
    public let lightText: UIColor

    init(bundle: Bundle, traitCollection: UITraitCollection?) {
        primary = UIColor(named: "primary", in: bundle, compatibleWith: traitCollection)!
        dark = UIColor(named: "dark", in: bundle, compatibleWith: traitCollection)!
        light = UIColor(named: "light", in: bundle, compatibleWith: traitCollection)!
        lightText = UIColor(named: "lightText", in: bundle, compatibleWith: traitCollection)!
    }
}

@objc(OBAThemeFonts)
public class ThemeFonts: NSObject {
    private static let maxFontSize: CGFloat = 32.0

    private var _body: UIFont?
    public lazy var body: UIFont = {
        if let body = _body {
            return body
        }

        _body = ThemeFonts.font(textStyle: UIFont.TextStyle.body)
        return _body!
    }()

    class func font(textStyle: UIFont.TextStyle) -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle)
        return UIFont.init(descriptor: descriptor, size: min(descriptor.pointSize, maxFontSize))
    }
}
