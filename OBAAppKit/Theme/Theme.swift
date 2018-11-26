//
//  Theme.swift
//  OBAAppKit
//
//  Created by Aaron Brethorst on 11/25/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit

@objc(OBATheme)
public class Theme: NSObject {
    public let colors: ThemeColors
    public let fonts: ThemeFonts

    public init(bundle: Bundle?, traitCollection: UITraitCollection?) {
        colors = ThemeColors(bundle: bundle ?? Bundle(for: Theme.self), traitCollection: traitCollection)
        fonts = ThemeFonts()
    }
}

@objc(OBAThemeColors)
public class ThemeColors: NSObject {
    public let primary: UIColor
    public let dark: UIColor
    public let light: UIColor

    init(bundle: Bundle, traitCollection: UITraitCollection?) {
        primary = UIColor(named: "primary", in: bundle, compatibleWith: traitCollection)!
        dark = UIColor(named: "dark", in: bundle, compatibleWith: traitCollection)!
        light = UIColor(named: "light", in: bundle, compatibleWith: traitCollection)!
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
