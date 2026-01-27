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

// Live Activities data contract for trip bookmark cell
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

// Wraps UIColor to make it Codable for ActivityKit storage
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

        color.getRed(&r, green: &g, blue: &b, alpha: &a)

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
