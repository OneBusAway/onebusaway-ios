//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

// Adapted from https://cocoacasts.com/from-hex-to-uicolor-and-back-in-swift
//
// Hex <-> UIColor conversion is the portable half of the UIColor extensions in
// UIKitExtensions.swift: `Route` decodes and encodes its colors as hex strings,
// so it has to build for watchOS too.
public extension UIColor {

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
}
