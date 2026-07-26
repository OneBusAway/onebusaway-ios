//
//  ReviewPromptPolicy.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// How a rider answered the sentiment prompt.
enum FeedbackPromptOutcome: String {
    case positive
    case negative
    case deferred
}

/// Decides whether to ask a rider how they're liking the app.
///
/// Pure policy: counts "success moments" handed to it by `StopViewModel`,
/// applies the backoffs, and derives eligibility. Owns no UI and performs no
/// presentation. Follows `DonationsManager`'s precedent of holding its own
/// `UserDefaults` keys rather than widening the `UserDataStore` protocol.
@MainActor
final class ReviewPromptPolicy {

    /// Successful real-time stop views required before asking.
    static let successThreshold = 5

    /// Maximum number of times a rider is ever asked.
    static let maximumAsks = 3

    private static let deferredBackoff: TimeInterval = 60 * 86400
    private static let negativeBackoff: TimeInterval = 180 * 86400

    private let userDefaults: UserDefaults
    private let bundle: Bundle
    private let now: () -> Date

    init(
        userDefaults: UserDefaults,
        bundle: Bundle = .main,
        now: @escaping () -> Date = Date.init
    ) {
        self.userDefaults = userDefaults
        self.bundle = bundle
        self.now = now
    }

    private enum Keys {
        static let successCount = "ReviewPrompt.successCount"
        static let askCount = "ReviewPrompt.askCount"
        static let lastAskedDate = "ReviewPrompt.lastAskedDate"
        static let outcome = "ReviewPrompt.outcome"
        static let lastVersionPrompted = "ReviewPrompt.lastVersionPrompted"
        static let alwaysShow = "ReviewPrompt.alwaysShow"
    }

    // MARK: - Recording

    /// Records one successful real-time stop view. Callers are responsible for
    /// debouncing to at most one call per stop view.
    func recordSuccess() {
        userDefaults.set(successCount + 1, forKey: Keys.successCount)
    }

    /// Called the moment the prompt appears — before the rider answers.
    ///
    /// Writes `.deferred` up front so a rider who backgrounds and kills the app
    /// mid-alert lands in a defined state rather than leaving `lastAskedDate`
    /// set against a stale or absent outcome. `recordOutcome` overwrites it.
    ///
    /// The two *permanent* gates — the three-ask lifetime cap and the version
    /// stamp — are skipped while the debug override is on. `alwaysShowPrompt`
    /// short-circuits `isPromptPending` ahead of both, so a QA pass would
    /// otherwise spend a budget it isn't subject to and silence the organic
    /// prompt on that install for good.
    func recordPromptPresented() {
        if !alwaysShowPrompt {
            userDefaults.set(askCount + 1, forKey: Keys.askCount)
            userDefaults.set(bundle.appVersion, forKey: Keys.lastVersionPrompted)
        }
        userDefaults.set(now(), forKey: Keys.lastAskedDate)
        userDefaults.set(FeedbackPromptOutcome.deferred.rawValue, forKey: Keys.outcome)
        userDefaults.set(0, forKey: Keys.successCount)
    }

    /// Records how the rider actually answered.
    ///
    /// Skipped entirely while the debug override is on, for the same reason
    /// `recordPromptPresented()` skips the permanent gates: a QA tap on "Yes!" would
    /// otherwise write `.positive`, and the moment the toggle went back off the organic
    /// prompt would be silenced on that install for good.
    ///
    /// Defends against being called without a preceding `recordPromptPresented()`:
    /// with no `lastAskedDate` on file, `.negative`/`.deferred` would otherwise be a
    /// total no-op — the backoff `if let` in `isPromptPending` is skipped entirely,
    /// and `successCount` was never zeroed, so the rider stays pending and gets
    /// re-prompted on every subsequent stop view without ever burning an ask. Stamp
    /// `lastAskedDate` and zero `successCount` here too, so the ask is always
    /// consumed regardless of call order.
    func recordOutcome(_ outcome: FeedbackPromptOutcome) {
        guard !alwaysShowPrompt else { return }

        userDefaults.set(outcome.rawValue, forKey: Keys.outcome)
        if userDefaults.object(forKey: Keys.lastAskedDate) == nil {
            userDefaults.set(now(), forKey: Keys.lastAskedDate)
            userDefaults.set(0, forKey: Keys.successCount)
        }
    }

    // MARK: - Eligibility

    /// Whether the prompt should be shown at the next natural stopping point.
    ///
    /// Derived on every read rather than stored. A stored edge-triggered flag
    /// would be lost when the app terminates and could never be re-set, because
    /// `recordSuccess()` would never again *cross* a threshold it is already
    /// past — stranding the rider at five successes and no prompt forever.
    var isPromptPending: Bool {
        guard bundle.feedbackPromptEnabled else { return false }

        // Without an App Store ID the positive branch has nowhere to go: the rider taps
        // "Yes!", `openWriteReviewPage()` bails, and `.positive` is recorded — closing the
        // prompt permanently for someone who was never actually asked anything answerable.
        // Only OneBusAway configures `AppStoreID`, so every other white-label target would
        // hit this. `MoreViewController` hides its Rate row on the same condition.
        guard bundle.appStoreID != nil else { return false }

        if alwaysShowPrompt { return true }
        guard askCount < Self.maximumAsks else { return false }
        guard outcome != .positive else { return false }
        guard successCount >= Self.successThreshold else { return false }
        guard userDefaults.string(forKey: Keys.lastVersionPrompted) != bundle.appVersion else {
            return false
        }

        if let lastAsked = userDefaults.object(forKey: Keys.lastAskedDate) as? Date {
            let backoff: TimeInterval = outcome == .negative ? Self.negativeBackoff : Self.deferredBackoff
            guard now() >= lastAsked.addingTimeInterval(backoff) else { return false }
        }

        return true
    }

    // MARK: - Debug

    /// Debug override: bypasses the counter, backoffs, version gate, and
    /// lifetime cap. Does not bypass the `FeedbackPromptEnabled` kill switch.
    ///
    /// Presentations made under this toggle don't spend the lifetime ask count or
    /// stamp the version gate — see `recordPromptPresented()`.
    var alwaysShowPrompt: Bool {
        get { userDefaults.bool(forKey: Keys.alwaysShow) }
        set { userDefaults.set(newValue, forKey: Keys.alwaysShow) }
    }

    /// Clears every persisted key *except* the debug override, so QA can re-run the
    /// flow from scratch without the toggle switching itself off underneath them.
    /// The Settings footer promises exactly this.
    func reset() {
        for key in [Keys.successCount, Keys.askCount, Keys.lastAskedDate,
                    Keys.outcome, Keys.lastVersionPrompted] {
            userDefaults.removeObject(forKey: key)
        }
    }

    // MARK: - Internals

    /// Successes recorded since the last reset. Internal rather than private so
    /// `StopViewModelTests` can assert on it — those tests drive a real
    /// `Application`, so this is the only observable the recording path exposes.
    var successCount: Int { userDefaults.integer(forKey: Keys.successCount) }

    private var askCount: Int { userDefaults.integer(forKey: Keys.askCount) }

    /// The most recently recorded outcome. Internal rather than private so tests
    /// can pin the presentation-time write in `recordPromptPresented()` — that
    /// `.deferred` write happens before the rider answers, and nothing else in the
    /// public interface makes it observable.
    var outcome: FeedbackPromptOutcome? {
        guard let raw = userDefaults.string(forKey: Keys.outcome) else { return nil }
        return FeedbackPromptOutcome(rawValue: raw)
    }
}
