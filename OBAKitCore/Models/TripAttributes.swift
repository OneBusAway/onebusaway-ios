//
//  TripAttributes.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import ActivityKit
import UIKit

/// Live Activities data contract for trip bookmark tracking.
public struct TripAttributes: ActivityAttributes {
    public struct StaticData: Codable, Hashable {
        public let routeShortName: String
        public let routeHeadsign: String
        public let stopID: String

        public init(routeShortName: String, routeHeadsign: String, stopID: String) {
            self.routeShortName = routeShortName
            self.routeHeadsign = routeHeadsign
            self.stopID = stopID
        }
    }

    public struct MinuteInfo: Codable, Hashable {
        public let text: String
        public let color: CodableColor

        public init(text: String, color: UIColor) {
            self.text = text
            self.color = CodableColor(color)
        }
    }

    public struct ContentState: Codable, Hashable {
        public let statusText: String
        public let statusColor: CodableColor
        public let minutes: [MinuteInfo]
        public let shouldHighlight: Bool

        public init(statusText: String, statusColor: UIColor, minutes: [MinuteInfo], shouldHighlight: Bool = false) {
            self.statusText = statusText
            self.statusColor = CodableColor(statusColor)
            self.minutes = minutes
            self.shouldHighlight = shouldHighlight
        }
    }

    public let staticData: StaticData

    public init(staticData: StaticData) {
        self.staticData = staticData
    }
}

// MARK: - CodableColor Wrapper

/// Wraps `UIColor` to make it `Codable` for ActivityKit storage.
///
/// Colors are converted to the sRGB color space before extracting components,
/// ensuring correct encoding even for colors in extended color spaces (e.g., Display P3).
public struct CodableColor: Codable, Hashable {
    private let red: CGFloat
    private let green: CGFloat
    private let blue: CGFloat
    private let alpha: CGFloat

    public init(_ color: UIColor) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        // Convert to sRGB to guarantee getRed succeeds. UIColor.getRed returns
        // false for colors not in a compatible color space.
        let sRGBColor: UIColor
        if let converted = color.cgColor.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB)!,
            intent: .defaultIntent,
            options: nil
        ) {
            sRGBColor = UIColor(cgColor: converted)
        } else {
            sRGBColor = color
        }

        guard sRGBColor.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            // Fallback: opaque black if conversion still fails (should not happen).
            self.red = 0
            self.green = 0
            self.blue = 0
            self.alpha = 1
            return
        }

        self.red = r
        self.green = g
        self.blue = b
        self.alpha = a
    }

    public var uiColor: UIColor {
        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - Convenience Extensions

extension TripAttributes.MinuteInfo {
    public var uiColor: UIColor {
        return color.uiColor
    }
}

extension TripAttributes.ContentState {
    public var uiStatusColor: UIColor {
        return statusColor.uiColor
    }
}
