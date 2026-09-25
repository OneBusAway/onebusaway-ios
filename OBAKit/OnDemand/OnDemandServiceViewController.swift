//
//  OnDemandServiceViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import OBAKitCore
import SwiftUI
import UIKit

/// UIKit host for `OnDemandServiceView`, so `ViewRouter` can push it and the
/// map can present it as a sheet like the rental detail.
///
/// The booking line is a function of `now` (spec §6.6), so the summary is
/// rebuilt whenever the page comes back into view, when the app returns to
/// the foreground, and at the next instant the line can change — a rider who
/// calls and comes back after the cutoff must not still read "Book by today".
///
/// Those rebuilds walk up to a year of service dates per rule, so they run
/// off the main actor; only the first, in `init`, is synchronous, because the
/// hosting controller needs a complete root view to show.
final class OnDemandServiceViewController: UIHostingController<OnDemandServiceView> {

    private let service: OnDemandService
    private let now: () -> Date
    private let onOpenURL: (URL) -> Void
    private var boundaryRefreshTask: Task<Void, Never>?
    /// The in-flight rebuild; exposed so tests can await it.
    private(set) var summaryBuildTask: Task<Void, Never>?

    /// - Parameter now: The device wall clock; injectable for tests.
    init(application: Application, service: OnDemandService, now: @escaping () -> Date = Date.init) {
        self.service = service
        self.now = now
        self.onOpenURL = { [weak application] url in application?.open(url, options: [:], completionHandler: nil) }
        super.init(rootView: Self.makeView(service: service, now: now(), onOpenURL: onOpenURL))
        title = service.name

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        boundaryRefreshTask?.cancel()
        summaryBuildTask?.cancel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshSummary()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // `viewWillAppear` rebuilds and reschedules on the way back.
        summaryBuildTask?.cancel()
        summaryBuildTask = nil
        boundaryRefreshTask?.cancel()
        boundaryRefreshTask = nil
    }

    /// An off-screen page (pushed under another, or in a dismissed sheet
    /// still being torn down) refreshes on its next `viewWillAppear`.
    @objc private func applicationWillEnterForeground() {
        guard viewIfLoaded?.window != nil else { return }
        refreshSummary()
    }

    /// Rebuilds the summary against the current clock off the main actor,
    /// then shows it and re-arms the one-shot refresh for its next boundary.
    /// A newer call supersedes a build still running.
    func refreshSummary() {
        summaryBuildTask?.cancel()
        let service = service
        let now = now()
        summaryBuildTask = Task { [weak self] in
            let summary = await Self.buildSummary(service: service, now: now)
            guard !Task.isCancelled, let self else { return }
            rootView = OnDemandServiceView(service: service, summary: summary, onOpenURL: onOpenURL)
            scheduleBoundaryRefresh(at: summary.nextChangeInstant)
        }
    }

    private func scheduleBoundaryRefresh(at instant: Date?) {
        boundaryRefreshTask?.cancel()
        guard let instant else {
            boundaryRefreshTask = nil
            return
        }
        // A second past the boundary, so the rebuild lands strictly after it.
        let delay = max(instant.timeIntervalSince(now()), 0) + 1
        boundaryRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refreshSummary()
        }
    }

    private static func makeView(service: OnDemandService, now: Date, onOpenURL: @escaping (URL) -> Void) -> OnDemandServiceView {
        OnDemandServiceView(service: service, summary: makeSummary(service: service, now: now), onOpenURL: onOpenURL)
    }

    @concurrent
    private nonisolated static func buildSummary(service: OnDemandService, now: Date) async -> OnDemandServiceSummary {
        makeSummary(service: service, now: now)
    }

    /// A nil zone still yields hours and contact details; only the deadline
    /// line drops out.
    private nonisolated static func makeSummary(service: OnDemandService, now: Date) -> OnDemandServiceSummary {
        OnDemandServiceSummary(service: service, timeZone: service.timeZone, now: now, locale: .current)
    }
}
