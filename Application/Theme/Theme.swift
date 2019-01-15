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

    public let padding: CGFloat = 8.0

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

    /// A gray text color, used on light backgrounds for de-emphasized text.
    public let subduedText: UIColor

    init(bundle: Bundle, traitCollection: UITraitCollection?) {
        primary = UIColor(named: "primary", in: bundle, compatibleWith: traitCollection)!
        dark = UIColor(named: "dark", in: bundle, compatibleWith: traitCollection)!
        light = UIColor(named: "light", in: bundle, compatibleWith: traitCollection)!
        lightText = UIColor(named: "lightText", in: bundle, compatibleWith: traitCollection)!
        subduedText = UIColor(named: "subduedText", in: bundle, compatibleWith: traitCollection)!
    }
}

@objc(OBAThemeFonts)
public class ThemeFonts: NSObject {
    private static let maxFontSize: CGFloat = 32.0

    // MARK: - Title

    private var _title: UIFont?
    public lazy var title: UIFont = {
        if let title = _title {
            return title
        }

        _title = ThemeFonts.boldFont(textStyle: UIFont.TextStyle.title1)
        return _title!
    }()

    // MARK: - Body

    private var _body: UIFont?
    public lazy var body: UIFont = {
        if let body = _body {
            return body
        }

        _body = ThemeFonts.font(textStyle: UIFont.TextStyle.body)
        return _body!
    }()

    private var _boldBody: UIFont?
    public lazy var boldBody: UIFont = {
        if let boldBody = _boldBody {
            return boldBody
        }

        _boldBody = ThemeFonts.boldFont(textStyle: UIFont.TextStyle.body)
        return _boldBody!
    }()

    // MARK: - Footnote

    private var _footnote: UIFont?
    public lazy var footnote: UIFont = {
        if let footnote = _footnote {
            return footnote
        }

        _footnote = ThemeFonts.font(textStyle: UIFont.TextStyle.footnote)
        return _footnote!
    }()

    private class func font(textStyle: UIFont.TextStyle) -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle)
        return UIFont(descriptor: descriptor, size: min(descriptor.pointSize, maxFontSize))
    }

    private class func boldFont(textStyle: UIFont.TextStyle) -> UIFont {
        let plainDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle)
        let augmentedDescriptor = plainDescriptor.withSymbolicTraits(.traitBold)
        let descriptor = augmentedDescriptor ?? plainDescriptor
        return UIFont(descriptor: descriptor, size: min(descriptor.pointSize, maxFontSize))
    }
}
