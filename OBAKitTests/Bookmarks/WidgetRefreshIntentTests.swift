//
//  WidgetRefreshIntentTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
nonisolated struct WidgetRefreshIntentTests {

    private static let seedDate = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func `Initial tap triggers timeline reload`() async {
        let clock = SimulatedClock(initialDate: Self.seedDate)
        let counter = ReloadCounter()

        let reloader = WidgetTimelineReloader(
            cooldownInterval: 5.0,
            clock: { clock.now },
            reloadAction: { counter.increment() }
        )

        let result = await reloader.reload()

        #expect(result == .success)
        #expect(result == .reloaded)
        #expect(counter.count == 1)
    }

    @Test func `Immediate repeated tap within cooldown interval skips redundant reload without error`() async {
        let clock = SimulatedClock(initialDate: Self.seedDate)
        let counter = ReloadCounter()

        let reloader = WidgetTimelineReloader(
            cooldownInterval: 5.0,
            clock: { clock.now },
            reloadAction: { counter.increment() }
        )

        let firstResult = await reloader.reload()
        #expect(firstResult == .success)
        #expect(counter.count == 1)

        // Advance 1 second (well within 5s cooldown)
        clock.advance(by: 1.0)

        let secondResult = await reloader.reload()
        #expect(secondResult == .throttled)
        #expect(counter.count == 1)

        // Rapid bursts within cooldown are all throttled
        for _ in 0..<5 {
            clock.advance(by: 0.5)
            let burstResult = await reloader.reload()
            #expect(burstResult == .throttled)
        }
        #expect(counter.count == 1)
    }

    @Test func `Subsequent tap after cooldown triggers reload`() async {
        let clock = SimulatedClock(initialDate: Self.seedDate)
        let counter = ReloadCounter()

        let reloader = WidgetTimelineReloader(
            cooldownInterval: 5.0,
            clock: { clock.now },
            reloadAction: { counter.increment() }
        )

        _ = await reloader.reload()
        #expect(counter.count == 1)

        // Advance past 5s cooldown (e.g. 5.1s)
        clock.advance(by: 5.1)

        let afterCooldownResult = await reloader.reload()
        #expect(afterCooldownResult == .success)
        #expect(counter.count == 2)
    }

    @Test func `Simulated error or unavailable state does not trap`() async {
        let clock = SimulatedClock(initialDate: Self.seedDate)

        // Failure simulation
        let failingReloader = WidgetTimelineReloader(
            cooldownInterval: 5.0,
            clock: { clock.now },
            reloadAction: {
                throw WidgetReloadError.failed
            }
        )

        let failureResult = await failingReloader.reload()
        #expect(failureResult == .failure)

        // Unavailable simulation
        let unavailableReloader = WidgetTimelineReloader(
            cooldownInterval: 5.0,
            clock: { clock.now },
            reloadAction: {
                throw WidgetReloadError.unavailable
            }
        )

        let unavailableResult = await unavailableReloader.reload()
        #expect(unavailableResult == .unavailable)

        // Generic NSError simulation
        let genericErrorReloader = WidgetTimelineReloader(
            cooldownInterval: 5.0,
            clock: { clock.now },
            reloadAction: {
                throw NSError(domain: "test.domain", code: -999, userInfo: nil)
            }
        )

        let genericResult = await genericErrorReloader.reload()
        #expect(genericResult == .failure)
    }

    @Test func `Reset clears cooldown state allowing immediate reload`() async {
        let clock = SimulatedClock(initialDate: Self.seedDate)
        let counter = ReloadCounter()

        let reloader = WidgetTimelineReloader(
            cooldownInterval: 5.0,
            clock: { clock.now },
            reloadAction: { counter.increment() }
        )

        _ = await reloader.reload()
        #expect(counter.count == 1)

        // Without reset, immediate reload would be throttled
        clock.advance(by: 0.5)
        await reloader.reset()

        let result = await reloader.reload()
        #expect(result == .success)
        #expect(counter.count == 2)
    }
}

// MARK: - Test Helpers

private nonisolated final class ReloadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    func increment() {
        lock.lock()
        _count += 1
        lock.unlock()
    }
}

private nonisolated final class SimulatedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    init(initialDate: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self._now = initialDate
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return _now
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        _now = _now.addingTimeInterval(seconds)
        lock.unlock()
    }
}
