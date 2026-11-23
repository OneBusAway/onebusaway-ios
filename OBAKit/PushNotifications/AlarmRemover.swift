//
//  AlarmRemover.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

extension Notification.Name {
    /// Posted by `AlarmRemover` once an alarm is gone, on the app's notification
    /// center and on the main actor only: observers handle it synchronously. The
    /// alarm's URL is under `AlarmRemover.alarmURLKey`. A stop page showing the
    /// departure drops its bell without waiting for a refresh.
    static let alarmRemoved = Notification.Name("OBA.AlarmRemoved")
}

/// Deletes an alarm the one way the stop page, the trip page and the Recent tab
/// all do: on the Obaco server first, then the local copy, then tells the other
/// screens it's gone.
///
/// Server first, so a failure leaves the rider an alarm they can still see and
/// cancel. Deleting only the local copy would leave a notification they could no
/// longer stop.
@MainActor
struct AlarmRemover {
    static let alarmURLKey = "alarmURL"

    let obacoService: ObacoAPIService?
    let deleteLocalCopy: (Alarm) -> Void
    let notificationCenter: NotificationCenter

    init(obacoService: ObacoAPIService?, deleteLocalCopy: @escaping (Alarm) -> Void, notificationCenter: NotificationCenter) {
        self.obacoService = obacoService
        self.deleteLocalCopy = deleteLocalCopy
        self.notificationCenter = notificationCenter
    }

    init(application: Application) {
        self.init(
            obacoService: application.obacoService,
            deleteLocalCopy: { [userDataStore = application.userDataStore] in userDataStore.delete(alarm: $0) },
            notificationCenter: application.notificationCenter
        )
    }

    /// Throws when the server copy couldn't be deleted, leaving the local copy
    /// alone. An alarm the server no longer has has already fired: that counts as
    /// deleted.
    func remove(_ alarm: Alarm) async throws {
        do {
            guard let obacoService else {
                throw StopViewModel.AlarmCancellationError.serviceUnavailable
            }
            try await obacoService.deleteAlarm(url: alarm.url)
        } catch APIError.requestNotFound {
            // It already fired, and the server deleted it.
        }
        deleteLocalCopy(alarm)
        notificationCenter.post(name: .alarmRemoved, object: nil, userInfo: [Self.alarmURLKey: alarm.url])
    }
}

/// A list's alarm deletions in flight, for a list that shows alarms and lets the
/// rider delete them: the Recent tab's and the home sheet's.
///
/// The list drops a row the moment its delete starts, so a swipe's animation
/// matches the data, and keeps it off through `isPending(_:)` until the server
/// answers: the store drops its copy only after that. If the server keeps the
/// alarm, the list's reload brings it back in its place, where the rider can see
/// it and try again.
@MainActor
final class PendingAlarmDeletions {
    private var pending = Set<URL>()
    private let application: Application

    init(application: Application) {
        self.application = application
    }

    /// Whether the alarm's delete is still on its way, which keeps it off the list.
    func isPending(_ alarm: Alarm) -> Bool {
        pending.contains(alarm.url)
    }

    /// Deletes through `AlarmRemover`, then calls `onFinish` either way, for the
    /// list to reload. Returns `nil` when this alarm's delete is already on its
    /// way: a second request would race the first.
    ///
    /// The remover is captured directly, so the DELETE still runs if the list
    /// goes away mid-request.
    func delete(_ alarm: Alarm, onFinish: @escaping @MainActor () -> Void) -> Task<Void, Never>? {
        guard pending.insert(alarm.url).inserted else { return nil }
        let remover = AlarmRemover(application: application)
        let application = application
        return Task { [weak self] in
            do {
                try await remover.remove(alarm)
                self?.pending.remove(alarm.url)
                onFinish()
            } catch {
                Logger.error("Failed to delete alarm: \(error.localizedDescription)")
                self?.pending.remove(alarm.url)
                onFinish()
                await application.displayError(error)
            }
        }
    }
}
