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

/// The Live Activity countdown ticks through `Text(_:format:)` with a time
/// data source. The Lock Screen draws that out of process, and at full
/// brightness it drew our own custom `DiscreteFormatStyle` as a redacted
/// placeholder card: raise the phone and every field went grey (#1583). Only
/// Apple's own format styles are safe there.
@Suite(.serialized)
struct TickingCountdownTextTests {

    private let departure = Date(timeIntervalSince1970: 1_700_000_000)
    private let english = Locale(identifier: "en_US")

    // MARK: - Visible: "8m"

    @Test func `The visible countdown uses a Foundation format style`() {
        let style = TickingCountdownText.visibleFormat(locale: english)
        #expect(String(reflecting: type(of: style)).hasPrefix("Foundation."))
    }

    /// Truncates like the Stop page's `8m`, so the two agree.
    @Test func `Eight and a half minutes out reads 8m`() {
        #expect(TickingCountdownText.snapshot(departure: departure, now: departure.addingTimeInterval(-510), locale: english) == "8m")
    }

    @Test func `Under a minute reads 0m`() {
        #expect(TickingCountdownText.snapshot(departure: departure, now: departure.addingTimeInterval(-30), locale: english) == "0m")
    }

    /// A departed arrival can sit on the card until the next push; the static
    /// snapshot must not build a backwards range, which traps.
    @Test func `Past departure the snapshot reads 0m`() {
        #expect(TickingCountdownText.snapshot(departure: departure, now: departure.addingTimeInterval(90), locale: english) == "0m")
    }

    // MARK: - Spoken: "in 8 minutes"

    /// VoiceOver reads a bare "8m" as "8 meters", so it hears the spelled-out form.
    @Test func `The spoken countdown uses a SwiftUI system format style`() {
        let style = TickingCountdownText.spokenFormat(departure: departure, locale: english)
        #expect(String(reflecting: type(of: style)).hasPrefix("SwiftUI."))
    }

    @Test func `Eight minutes out is spoken as in 8 minutes`() {
        #expect(TickingCountdownText.spokenSnapshot(departure: departure, now: departure.addingTimeInterval(-485), locale: english) == "in 8 minutes")
    }

    @Test func `At departure it is spoken as now`() {
        #expect(TickingCountdownText.spokenSnapshot(departure: departure, now: departure, locale: english) == "now")
    }
}
