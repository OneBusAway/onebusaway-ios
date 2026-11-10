//
//  ScheduleViewsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// What the stop and route schedule screens show for each load state. Both
/// views switch on `ScheduleContentState`; hosted SwiftUI text can't be read in
/// the test host, so the decision is tested here and each view model's
/// `contentState` is tested in its own suite.
@MainActor
@Suite(.serialized)
struct ScheduleViewsTests {

    private struct LoadFailure: Error {}

    /// A plain name for the state, so a mismatch prints readably.
    private func kind(_ state: ScheduleContentState) -> String {
        switch state {
        case .loading: "loading"
        case .failed: "failed"
        case .content: "content"
        case .empty: "empty"
        }
    }

    // MARK: - Content state

    @Test func `Loading with nothing to show yet shows the spinner`() {
        let state = ScheduleContentState(isLoading: true, hasContent: false, error: nil)
        #expect(kind(state) == "loading")
    }

    /// Changing the date reloads, and the old schedule stays up until the new one lands.
    @Test func `A reload keeps the loaded schedule on screen`() {
        let state = ScheduleContentState(isLoading: true, hasContent: true, error: nil)
        #expect(kind(state) == "content")
    }

    /// The screen's "No schedule data available" message.
    @Test func `Nothing to show once loading ends shows the empty message`() {
        let state = ScheduleContentState(isLoading: false, hasContent: false, error: nil)
        #expect(kind(state) == "empty")
    }

    @Test func `A first load that fails shows the error, not the empty message`() {
        let state = ScheduleContentState(isLoading: false, hasContent: false, error: LoadFailure())
        #expect(kind(state) == "failed")
    }

    @Test func `The error shown is the one the load failed with`() {
        let failure = NSError(domain: "ScheduleViewsTests", code: 42)
        guard case .failed(let shown) = ScheduleContentState(isLoading: false, hasContent: true, error: failure) else {
            Issue.record("Expected the error to be shown")
            return
        }
        #expect((shown as NSError).code == 42)
    }
}
