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
final class OnDemandServiceViewController: UIHostingController<OnDemandServiceView> {

    private let service: OnDemandService
    private let now: () -> Date
    private let onOpenURL: (URL) -> Void
    private var boundaryRefreshTask: Task<Void, Never>?

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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshSummary()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // `viewWillAppear` rebuilds and reschedules on the way back.
        boundaryRefreshTask?.cancel()
        boundaryRefreshTask = nil
    }

    /// An off-screen page (pushed under another, or in a dismissed sheet
    /// still being torn down) refreshes on its next `viewWillAppear`.
    @objc private func applicationWillEnterForeground() {
        guard viewIfLoaded?.window != nil else { return }
        refreshSummary()
    }

    /// Rebuilds the summary against the current clock and re-arms the
    /// one-shot refresh for its next boundary.
    func refreshSummary() {
        rootView = Self.makeView(service: service, now: now(), onOpenURL: onOpenURL)
        scheduleBoundaryRefresh(at: rootView.summary.nextChangeInstant)
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

    /// A nil zone still yields hours and contact details; only the deadline
    /// line drops out.
    private static func makeView(service: OnDemandService, now: Date, onOpenURL: @escaping (URL) -> Void) -> OnDemandServiceView {
        let summary = OnDemandServiceSummary(service: service, timeZone: service.timeZone, now: now, locale: .current)
        return OnDemandServiceView(service: service, summary: summary, onOpenURL: onOpenURL)
    }
}
