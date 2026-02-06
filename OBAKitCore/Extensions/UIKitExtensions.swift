//
//  UIKit.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

/// Protocol support for improving Auto Layout-compatible view creation.
public protocol Autolayoutable {
    static func autolayoutNew() -> Self
}

#if os(iOS)
extension UIView: Autolayoutable {
    /// Creates a new instance of the receiver class, configured for use with Auto Layout.
    ///
    /// - Returns: An instance of the receiver class.
    public static func autolayoutNew() -> Self {
        let view = self.init(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }
}
#endif

#if os(iOS)
extension UIView {
    /// Returns true if the app's is running in a right-to-left language, like Hebrew or Arabic.
    public var layoutDirectionIsRTL: Bool {
        return UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft
    }

    /// Returns true if the app's is running in a left-to-right language, like English.
    public var layoutDirectionIsLTR: Bool {
        return UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .leftToRight
    }
}
#endif

// MARK: - UIColor

// Adapted from https://cocoacasts.com/from-hex-to-uicolor-and-back-in-swift
public extension UIColor {

    /// Returns the accent color defined in the app's xcasset bundle. Make sure this is set, or calling it will crash the app!
    static var accentColor: UIColor {
        return UIColor(named: "AccentColor")!
    }

    /// Initializes a `UIColor` using `0-255` range `Int` values.
    /// - Parameter r: Red, `0-255`.
    /// - Parameter g: Green, `0-255`.
    /// - Parameter b: Blue, `0-255`.
    /// - Parameter a: Alpha, `0.0-1.0`. Default is `1.0`.
    convenience init(r: Int, g: Int, b: Int, a: CGFloat = 1.0) {
        self.init(red: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: a)
    }

    /// Initialize a `UIColor` object with a hex string. Supports either "#FFFFFF" or "FFFFFF" styles.
    ///
    /// - Parameter hex: The hex string to turn into a `UIColor`.
    convenience init?(hex: String?) {
        guard let hex = hex else {
            return nil
        }

        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0

        let length = hexSanitized.count

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0

        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0

        } else {
            return nil
        }

        self.init(red: r, green: g, blue: b, alpha: a)
    }

    // MARK: - Computed Properties

    var toHex: String? {
        return toHex()
    }

    // MARK: - From UIColor to String

    /// Generates a hex value from the receiver
    ///
    /// The hex values _do not_ have leading `#` values.
    /// In other words, `UIColor.red` -> `ff0000`.
    ///
    /// - Parameter alpha: Whether to include the alpha channel.
    /// - Returns: The hex string.
    func toHex(alpha: Bool = false) -> String? {
        let components = cgColor.components
        let numberOfComponents = cgColor.numberOfComponents

        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1

        switch numberOfComponents {
        case 2: // Grayscale
            r = components?[0] ?? 0
            g = components?[0] ?? 0
            b = components?[0] ?? 0
            a = components?[1] ?? 1
        case 4: // RGBA
            r = components?[0] ?? 0
            g = components?[1] ?? 0
            b = components?[2] ?? 0
            a = components?[3] ?? 1
        default:
            return nil
        }

        if alpha {
            return String(format: "%02lX%02lX%02lX%02lX",
                          lroundf(Float(r) * 255),
                          lroundf(Float(g) * 255),
                          lroundf(Float(b) * 255),
                          lroundf(Float(a) * 255))
        } else {
            return String(format: "%02lX%02lX%02lX",
                          lroundf(Float(r) * 255),
                          lroundf(Float(g) * 255),
                          lroundf(Float(b) * 255))
        }
    }

    // MARK: - Luminance

    /// Returns a dark text color if the receiver is light, and light if the receiver is dark.
    var contrastingTextColor: UIColor {
        if isLightColor {
            #if os(watchOS)
            return .black
            #else
            return .darkText
            #endif
        }
        else {
            #if os(watchOS)
            return .white
            #else
            return .lightText
            #endif
        }
    }

    /// Determine if the receiver is a 'light' or 'dark' color.
    var isLightColor: Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        self.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        // Calculating the Perceived Luminance
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        return luminance > 0.5
    }

    /// Lightens the receiver by the specified percent.'
    /// - Parameter percentage: The percent by which to lighten the receiver. Defaults to 25%.
    /// - Returns: The lightened color.
    func lighten(by percentage: CGFloat = 0.25) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return self
        }

        return UIColor(
            red: min(red + percentage, 1.0),
            green: min(green + percentage, 1.0),
            blue: min(blue + percentage, 1.0),
            alpha: alpha
        )
    }
}

// MARK: - UIEdgeInsets

public extension UIEdgeInsets {

    /// Provides a way to bridge between libraries that use the deprecated `UIEdgeInsets` struct and `NSDirectionalEdgeInsets`.
    ///
    /// - Parameter directionalInsets: Edge insets
    init(directionalInsets: NSDirectionalEdgeInsets) {
        self.init(top: directionalInsets.top, left: directionalInsets.leading, bottom: directionalInsets.bottom, right: directionalInsets.trailing)
    }
}

// MARK: - UIFont

// Adapted from https://spin.atomicobject.com/2018/02/02/swift-scaled-font-bold-italic/

#if os(iOS)
public extension UIFont {
    /// Returns a new font based upon the receiver with the specified traits added.
    /// - Parameter traits: The traits to add to `self`.
    func withTraits(traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return UIFont(descriptor: descriptor!, size: 0) // size 0 means keep the size as-is.
    }

    /// Returns a bold version of `self`.
    var bold: UIFont {
        return withTraits(traits: .traitBold)
    }

    /// Returns an italic version of `self`.
    var italic: UIFont {
        return withTraits(traits: .traitItalic)
    }
}
#endif

// MARK: - UILabel

#if os(iOS)
public extension UILabel {

    /// Creates a new autolayout `UILabel` that attempts to maintain full visibility. This means it will adjust
    /// its font size, font scale, then font tightening to maintain visibilty. It also adapts to the user's content
    /// size setting, provided you specify a valid `UIFont`.
    /// - parameter font: The font to set for this label. It is recommended that you use
    ///     `.preferredFont` so it will adjust for content size. The default is `.preferredFont(forTextStyle: .body)`.
    /// - parameter textColor: The text color to set. The default is `.label`.
    /// - parameter numberOfLines: The number of lines to set for this label. The default is `0`.
    /// - parameter minimumScaleFactor: The smallest multiplier for the current font size that
    ///     yields an acceptable font size to use when displaying the label’s text. The default is `1`, which means the font won't scale by default.
    class func obaLabel(font: UIFont = .preferredFont(forTextStyle: .body),
                        textColor: UIColor = ThemeColors.shared.label,
                        numberOfLines: Int = 0,
                        minimumScaleFactor: CGFloat = 1) -> Self {
        let label = Self.autolayoutNew()
        label.font = font
        label.textColor = textColor
        label.numberOfLines = numberOfLines
        label.minimumScaleFactor = minimumScaleFactor
        label.allowsDefaultTighteningForTruncation = true
        label.adjustsFontForContentSizeCategory = true
        label.adjustsFontSizeToFitWidth = true
        return label
    }
}
#endif
