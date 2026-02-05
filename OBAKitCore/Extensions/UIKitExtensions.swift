//
//  UIKit.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#if canImport(UIKit)
import UIKit
#elseif canImport(WatchKit)
import WatchKit
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

public extension UIFont {
    /// Returns a new font based upon the receiver with the specified traits added.
    /// - Parameter traits: The traits to add to `self`.
    func withTraits(traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return UIFont(descriptor: descriptor!, size: 0) // size 0 means keep the size as-is.
    }
}
