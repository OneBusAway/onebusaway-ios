//
//  PromptCoordinator.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import UIKit

/// The kinds of ask that compete for a rider's attention.
enum PromptKind: String {
    case review
    case donationModal
    case surveyPrompt
}

/// Owns the app's cross-feature interruption budget so a rider is never asked
/// for money and for feedback in the same sitting.
///
/// **Only interruptions and engagements register here — inline card renders
/// never do.** `DonationsManager.shouldRequestDonations` has no per-session
/// throttle and `StopPageView` re-reads it on every refresh tick, so treating a
/// visible donation card as an "ask" would pin the cooldown permanently open
/// and the review prompt could never fire. What counts is the rider opening the
/// donation modal or answering/dismissing a survey.
@MainActor
final class PromptCoordinator {

    /// How long a donation or survey engagement blocks the review prompt.
    static let engagementCooldown: TimeInterval = 14 * 86400

    private let userDefaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let now: () -> Date
    private var observer: NSObjectProtocol?

    private var shownThisSession: Set<PromptKind> = []

    /// Records the exact engagement-date write made by a `noteShown(_:)` call —
    /// the value it wrote (`writtenDate`) and what it overwrote
    /// (`previousDate`) — so a matching `noteNotShown(_:)` can restore it.
    /// Without this, gating a prompt (marking it shown to claim the session
    /// slot) and then not actually presenting it would leave the 14-day
    /// engagement cooldown running against a prompt the rider never saw.
    ///
    /// `noteNotShown(_:)` only restores when the persisted date still equals
    /// `writtenDate` — i.e. only ever undoes its own write. A genuine
    /// `noteSurveyEngaged()` call in between advances the persisted date past
    /// `writtenDate`, so the later `noteNotShown` correctly declines to
    /// restore (and would otherwise erase a real engagement).
    private struct PendingEngagementUndo {
        let previousDate: Date?
        let writtenDate: Date
    }

    /// Keyed by kind, not a single slot: two kinds can be mid-flight at once
    /// (a survey card gated but unpresented while a donation modal finishes
    /// presenting), and with one slot the second `noteShown` would silently
    /// evict the first one's undo record. Its `noteNotShown` would then find
    /// nothing to restore and leave the cooldown running for 14 days against a
    /// prompt the rider never saw.
    private var pendingEngagementUndo: [PromptKind: PendingEngagementUndo] = [:]

    /// Set when a stop load fails. A rider who just watched the app fail is not
    /// a rider to ask for five stars.
    var sawErrorThisSession = false

    init(
        userDefaults: UserDefaults,
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
        self.now = now

        observer = notificationCenter.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.beginNewSession() }
        }
    }

    isolated deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    private enum Keys {
        static let lastEngagementDate = "PromptCoordinator.lastEngagementDate"
    }

    // MARK: - Queries

    /// Whether the sentiment prompt may be presented right now.
    func canShowReviewPrompt() -> Bool {
        guard shownThisSession.isEmpty else { return false }
        guard !sawErrorThisSession else { return false }

        if let lastEngagement = userDefaults.object(forKey: Keys.lastEngagementDate) as? Date,
           now() < lastEngagement.addingTimeInterval(Self.engagementCooldown) {
            return false
        }

        return true
    }

    /// Whether inline donation and survey cards may render.
    ///
    /// Session-scoped and set by an event that fires at most once per session,
    /// so this is safe to read from `shouldRequestDonations` — which is re-read
    /// on every refresh tick — without the gate erasing the card the rider is
    /// currently looking at.
    func canShowInlineCards() -> Bool {
        !shownThisSession.contains(.review)
    }

    // MARK: - Recording

    func noteShown(_ kind: PromptKind) {
        shownThisSession.insert(kind)

        // A review prompt is not a donation/survey engagement; recording it as
        // one would start the very cooldown that gates the review prompt.
        if kind != .review {
            let previousEngagementDate = userDefaults.object(forKey: Keys.lastEngagementDate) as? Date
            let writtenDate = now()
            pendingEngagementUndo[kind] = PendingEngagementUndo(previousDate: previousEngagementDate, writtenDate: writtenDate)
            userDefaults.set(writtenDate, forKey: Keys.lastEngagementDate)
        }
    }

    /// Releases a session slot claimed by a prompt that was gated but never
    /// actually presented. `MapViewModel` already rolls its own survey flag
    /// back in this case.
    ///
    /// Also undoes the engagement-cooldown write from the matching
    /// `noteShown(_:)`, if any — a gated-but-unpresented prompt is not an
    /// engagement and must not block the review prompt for 14 days. Only
    /// restores when the persisted date still matches what that `noteShown(_:)`
    /// wrote, so a genuine `noteSurveyEngaged()` in between is never clobbered.
    func noteNotShown(_ kind: PromptKind) {
        shownThisSession.remove(kind)

        if let pending = pendingEngagementUndo.removeValue(forKey: kind) {
            let currentDate = userDefaults.object(forKey: Keys.lastEngagementDate) as? Date
            if currentDate == pending.writtenDate {
                if let previousDate = pending.previousDate {
                    userDefaults.set(previousDate, forKey: Keys.lastEngagementDate)
                } else {
                    userDefaults.removeObject(forKey: Keys.lastEngagementDate)
                }
            }
        }
    }

    /// The rider answered or dismissed a survey card.
    func noteSurveyEngaged() {
        userDefaults.set(now(), forKey: Keys.lastEngagementDate)
    }

    /// Starts a fresh foreground session.
    func beginNewSession() {
        shownThisSession.removeAll()
        sawErrorThisSession = false
        pendingEngagementUndo.removeAll()
    }

    /// Clears persisted cooldown state. Called by the debug reset so a QA
    /// tester isn't blocked for 14 days after resetting the policy.
    func reset() {
        userDefaults.removeObject(forKey: Keys.lastEngagementDate)
        beginNewSession()
    }
}
