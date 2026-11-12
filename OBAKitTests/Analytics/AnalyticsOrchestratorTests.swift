//
//  AnalyticsOrchestratorTests.swift
//  OBAKitTests
//

import Foundation
import Testing
@testable import App
@testable import OBAKit

@Suite(.serialized)
struct AnalyticsOrchestratorTests {

    @Test @MainActor
    func `Initial reporting preference follows UserDefaults`() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.set(true, forKey: AnalyticsKeys.reportingEnabledUserDefaultsKey)
        defer { defaults.removePersistentDomain(forName: #function) }

        let analytics = AnalyticsOrchestrator(userDefaults: defaults)

        #expect(analytics.reportingEnabled())
    }

    @Test @MainActor
    func `Changing reporting preference persists and is immediately readable`() {
        let defaults = UserDefaults(suiteName: #function)!
        defer { defaults.removePersistentDomain(forName: #function) }
        let analytics = AnalyticsOrchestrator(userDefaults: defaults)

        analytics.setReportingEnabled(false)
        #expect(!analytics.reportingEnabled())
        #expect(!defaults.bool(forKey: AnalyticsKeys.reportingEnabledUserDefaultsKey))

        analytics.setReportingEnabled(true)
        #expect(analytics.reportingEnabled())
        #expect(defaults.bool(forKey: AnalyticsKeys.reportingEnabledUserDefaultsKey))
    }

    @Test
    func `Concurrent preference mutations are serialized`() async {
        let state = AnalyticsReportingState(false)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<1_000 {
                group.addTask {
                    state.toggle()
                }
            }
        }

        #expect(!state.value)
    }
}
