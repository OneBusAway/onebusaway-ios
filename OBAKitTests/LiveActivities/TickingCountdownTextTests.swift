//
//  TickingCountdownTextTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import SwiftUI
import Testing
@testable import OBAKitCore

/// The Live Activity countdown ticks through `Text(.currentDate, format:)`.
/// The Lock Screen draws that out of process, and at full brightness it drew
/// our own `TripCountdownFormatStyle` as a redacted placeholder card: raise
/// the phone and every field went grey (#1583). Only SwiftUI's own system
/// styles are safe there.
@Suite(.serialized)
struct TickingCountdownTextTests {

    private let departure = Date(timeIntervalSince1970: 1_700_000_000)
    private let english = Locale(identifier: "en_US")

    @Test func `The live countdown uses a SwiftUI system format style`() {
        let style = TickingCountdownText.liveFormat(departure: departure, locale: english)
        #expect(String(reflecting: type(of: style)).hasPrefix("SwiftUI."))
    }

    @Test func `Eight minutes out reads in 8 minutes`() {
        let style = TickingCountdownText.liveFormat(departure: departure, locale: english)
        #expect(String(style.format(departure.addingTimeInterval(-485)).characters) == "in 8 minutes")
    }

    @Test func `At departure it reads now`() {
        let style = TickingCountdownText.liveFormat(departure: departure, locale: english)
        #expect(String(style.format(departure).characters) == "now")
    }

    /// Dim Lock Screen draws a static snapshot; raising the phone switches to
    /// the live text. The two must say the same thing, or the card jumps.
    @Test func `The dim snapshot matches the live countdown`() {
        let now = departure.addingTimeInterval(-485)
        let style = TickingCountdownText.liveFormat(departure: departure, locale: english)
        #expect(TickingCountdownText.snapshot(departure: departure, now: now, locale: english) == String(style.format(now).characters))
    }
}
