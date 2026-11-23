//
//  HomeAlarmsSectionModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import Foundation
import OBAKitCore

/// The home sheet's Alarms section: the alarms the rider has set, at the top of
/// Home while any are due.
///
/// Backed by `UserDataStore`, so reading it costs no network requests. Deleting
/// one goes to the server first, through `AlarmRemover`.
@MainActor
final class HomeAlarmsSectionModel: ObservableObject {

    /// An alarm with the deep link that reopens its trip.
    struct Item: Identifiable {
        let alarm: Alarm
        let deepLink: ArrivalDepartureDeepLink
        var id: URL { alarm.url }
    }

    /// The alarms still due that a row can open the trip for, in the store's
    /// order. An alarm stored without its deep link has nowhere to go.
    @Published private(set) var alarms: [Item] = []

    /// The section's title, which the UIKit Recent tab's Alarms section uses too.
    static var title: String {
        OBALoc("recent_stops_controller.alarms_section.title", value: "Alarms", comment: "Title of the Alarms section of the Recents controller")
    }

    /// The alarm whose trip is loading, so its row shows a spinner and a
    /// second tap doesn't load it again.
    @Published private(set) var openingAlarm: URL?

    private let application: Application
    private let pendingDeletions: PendingAlarmDeletions
    private var alarmFiredCancellable: AnyCancellable?

    init(application: Application) {
        self.application = application
        self.pendingDeletions = PendingAlarmDeletions(application: application)
        reload()
        // A fired alarm, or one deleted elsewhere (the stop or trip page), leaves
        // the store while home may be on screen, which no activation follows:
        // without this its row would linger.
        alarmFiredCancellable = NotificationCenter.default
            .publisher(for: .alarmFired)
            // `AlarmRemover` posts on the app's center.
            .merge(with: application.notificationCenter.publisher(for: .alarmRemoved))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
    }

    /// Re-reads the store, first sweeping out the alarms whose trip has passed.
    /// Publishes only when the list changed: this runs on every activation.
    func reload(now: Date = Date()) {
        application.userDataStore.deleteExpiredAlarms()
        let due = application.userDataStore.alarms.compactMap { alarm -> Item? in
            guard let deepLink = alarm.deepLink,
                  (alarm.tripDate ?? .distantPast) > now,
                  !pendingDeletions.isPending(alarm) else { return nil }
            return Item(alarm: alarm, deepLink: deepLink)
        }
        guard due.map(\.id) != alarms.map(\.id) else { return }
        alarms = due
    }

    /// Deletes through `AlarmRemover`: on the server first; see
    /// `PendingAlarmDeletions`.
    func delete(_ alarm: Alarm) {
        guard pendingDeletions.delete(alarm, onFinish: { [weak self] in self?.reload() }) != nil else { return }
        alarms.removeAll { $0.id == alarm.url }
    }

    /// The trip the alarm is set on, loaded for its row to open; `nil` while
    /// another is loading, or when it couldn't be (the error is shown).
    func loadTrip(for item: Item) async -> TripConvertible? {
        guard openingAlarm == nil else { return nil }
        openingAlarm = item.id
        defer { openingAlarm = nil }
        do {
            return try await application.loadTrip(item.deepLink)
        } catch {
            await application.displayError(error)
            return nil
        }
    }
}
