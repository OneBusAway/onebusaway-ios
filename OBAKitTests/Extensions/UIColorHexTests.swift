//
//  UIColorHexTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import UIKit
@testable import OBAKitCore

/// Tests for `UIColor` hex parsing (`init?(hex:)`) and hex serialization (`toHex(alpha:)`).
///
/// Validates 6-character and 8-character RGB/RGBA hex formatting, prefix handling (`#`),
/// case-insensitivity, whitespace trimming, invalid hex handling, and round-trip conversion.
@Suite(.serialized)
struct UIColorHexTests {

    // MARK: - 6-Digit Hex Initialization

    @Test func `init hex parses standard 6-digit hex string with hash prefix`() {
        let red = UIColor(hex: "#FF0000")
        #expect(red != nil)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        red?.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 1.0) < 0.001)
        #expect(abs(g - 0.0) < 0.001)
        #expect(abs(b - 0.0) < 0.001)
        #expect(abs(a - 1.0) < 0.001)
    }

    @Test func `init hex parses 6-digit hex string without hash prefix`() {
        let green = UIColor(hex: "00FF00")
        #expect(green != nil)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        green?.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 0.0) < 0.001)
        #expect(abs(g - 1.0) < 0.001)
        #expect(abs(b - 0.0) < 0.001)
        #expect(abs(a - 1.0) < 0.001)
    }

    @Test func `init hex parses lowercased 6-digit hex string`() {
        let blue = UIColor(hex: "#0000ff")
        #expect(blue != nil)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        blue?.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 0.0) < 0.001)
        #expect(abs(g - 0.0) < 0.001)
        #expect(abs(b - 1.0) < 0.001)
        #expect(abs(a - 1.0) < 0.001)
    }

    @Test func `init hex trims leading and trailing whitespace and newlines`() {
        let color = UIColor(hex: "  \n  #112233 \t ")
        #expect(color != nil)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color?.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - (0x11 / 255.0)) < 0.001)
        #expect(abs(g - (0x22 / 255.0)) < 0.001)
        #expect(abs(b - (0x33 / 255.0)) < 0.001)
        #expect(abs(a - 1.0) < 0.001)
    }

    // MARK: - 8-Digit Hex Initialization (RGBA)

    @Test func `init hex parses 8-digit RGBA hex string with alpha channel`() {
        let color = UIColor(hex: "#FF000080")
        #expect(color != nil)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color?.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 1.0) < 0.001)
        #expect(abs(g - 0.0) < 0.001)
        #expect(abs(b - 0.0) < 0.001)
        #expect(abs(a - (128.0 / 255.0)) < 0.01)
    }

    @Test func `init hex parses 8-digit hex without hash prefix`() {
        let color = UIColor(hex: "00FF00FF")
        #expect(color != nil)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color?.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(abs(r - 0.0) < 0.001)
        #expect(abs(g - 1.0) < 0.001)
        #expect(abs(b - 0.0) < 0.001)
        #expect(abs(a - 1.0) < 0.001)
    }

    // MARK: - Invalid Hex Inputs

    @Test func `init hex returns nil for nil string input`() {
        let nilString: String? = nil
        #expect(UIColor(hex: nilString) == nil)
    }

    @Test func `init hex returns nil for empty or whitespace-only strings`() {
        #expect(UIColor(hex: "") == nil)
        #expect(UIColor(hex: "   ") == nil)
        #expect(UIColor(hex: "#") == nil)
    }

    @Test func `init hex returns nil for invalid length strings`() {
        #expect(UIColor(hex: "#FFF") == nil)
        #expect(UIColor(hex: "12345") == nil)
        #expect(UIColor(hex: "1234567") == nil)
        #expect(UIColor(hex: "123456789") == nil)
    }

    @Test func `init hex returns nil for non-hex characters`() {
        #expect(UIColor(hex: "GG0000") == nil)
        #expect(UIColor(hex: "#ZZZZZZ") == nil)
    }

    // MARK: - toHex Serialization

    @Test func `toHex serializes standard RGB colors without alpha`() {
        let red = UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        #expect(red.toHex(alpha: false) == "FF0000")
        #expect(red.toHex == "FF0000")

        let green = UIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0)
        #expect(green.toHex(alpha: false) == "00FF00")

        let blue = UIColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0)
        #expect(blue.toHex(alpha: false) == "0000FF")
    }

    @Test func `toHex serializes with alpha channel when requested`() {
        let semiTransparentRed = UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.5)
        let hexWithAlpha = semiTransparentRed.toHex(alpha: true)
        #expect(hexWithAlpha != nil)
        #expect(hexWithAlpha?.hasPrefix("FF0000") == true)
        #expect(hexWithAlpha?.count == 8)
    }

    @Test func `toHex serializes grayscale colors correctly`() {
        let white = UIColor(white: 1.0, alpha: 1.0)
        #expect(white.toHex(alpha: false) == "FFFFFF")

        let black = UIColor(white: 0.0, alpha: 1.0)
        #expect(black.toHex(alpha: false) == "000000")
    }

    // MARK: - Round-Trip Conversion

    @Test func `hex to color and back round-trips consistently`() {
        let testHexes = ["FF5733", "33FF57", "3357FF", "1A1A1A", "EFEFEF"]
        for hex in testHexes {
            let color = UIColor(hex: hex)
            #expect(color != nil)
            #expect(color?.toHex(alpha: false)?.uppercased() == hex.uppercased())
        }
    }
}
