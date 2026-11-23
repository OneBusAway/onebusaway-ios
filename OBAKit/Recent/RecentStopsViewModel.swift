//
//  RecentStopsViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Combine
import Foundation
import OBAKitCore

@MainActor
final class RecentStopsViewModel: ObservableObject {

    enum BookmarkToggleResult: Equatable {
        case added
        case requiresConfirmation
        case multipleBookmarksRequireManagement
        case unavailable
    }

    @Published private(set) var alarms: [Alarm] = []
    @Published private(set) var recentStops: [Stop] = []
    @Published private(set) var bookmarkedStopIDs: Set<StopID> = []
    @Published var isShowingMultipleBookmarksAlert = false
    @Published private(set) var pendingBookmarkDeletion: Bookmark?

    private let application: Application
    // `viewWillAppear` calls `loadData()` every time the Recent tab is shown; without
    // this flag a user with no current region would flood the log on every tab switch.
    private var didWarnNilRegion = false
    private let pendingAlarmDeletions: PendingAlarmDeletions
    private var cancellables = Set<AnyCancellable>()

    init(application: Application) {
        self.application = application
        self.pendingAlarmDeletions = PendingAlarmDeletions(application: application)

        NotificationCenter.default.publisher(for: .bookmarksDidChange, object: application.userDataStore)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshBookmarkedStopIDs()
            }
            .store(in: &cancellables)

        refreshBookmarkedStopIDs()
    }

    /// - Parameter includesAlarms: Whether to load the alarms too. The map
    ///   panel's Recent tab doesn't list them: Home does.
    func loadData(includesAlarms: Bool = true) {
        if includesAlarms {
            application.userDataStore.deleteExpiredAlarms()
            alarms = application.userDataStore.alarms.filter { !pendingAlarmDeletions.isPending($0) }
        }
        refreshBookmarkedStopIDs()
        guard let currentRegion = application.currentRegion else {
            // No current region (mid-region-change, first launch race, denied location).
            // The user sees a generic empty state — log once per VM so the condition is
            // observable without spamming on every viewWillAppear.
            if !didWarnNilRegion {
                Logger.warn("RecentStopsViewModel.loadData: currentRegion is nil; returning empty recent stops.")
                didWarnNilRegion = true
            }
            recentStops = []
            return
        }
        // Region resolved — re-arm the warn so a *later* region loss is still observable.
        didWarnNilRegion = false
        let stops = application.userDataStore.recentStops(in: currentRegion)
        // Unchanged, as it usually is when a stacked sheet closes, it would
        // only redraw every row.
        if stops != recentStops {
            recentStops = stops
        }
    }

    func isBookmarked(_ stop: Stop) -> Bool {
        bookmarkedStopIDs.contains(stop.id)
    }

    @discardableResult
    func toggleBookmark(for stop: Stop) -> BookmarkToggleResult {
        guard let regionIdentifier = stop.regionIdentifier ?? application.currentRegion?.regionIdentifier else {
            return .unavailable
        }

        let matches = application.userDataStore.bookmarks.filter { bookmark in
            !bookmark.isTripBookmark &&
            bookmark.stopID == stop.id &&
            bookmark.regionIdentifier == regionIdentifier
        }

        switch matches.count {
        case 0:
            let bookmark = Bookmark(name: stop.name, regionIdentifier: regionIdentifier, stop: stop)
            application.userDataStore.add(bookmark, to: nil)
            refreshBookmarkedStopIDs()
            return .added
        case 1:
            pendingBookmarkDeletion = matches[0]
            return .requiresConfirmation
        default:
            isShowingMultipleBookmarksAlert = true
            return .multipleBookmarksRequireManagement
        }
    }

    func confirmBookmarkDeletion() {
        guard let bookmark = pendingBookmarkDeletion else { return }
        pendingBookmarkDeletion = nil
        BookmarkActions(application: application).reportDeletion(of: bookmark)
        application.userDataStore.delete(bookmark: bookmark)
        refreshBookmarkedStopIDs()
    }

    func cancelBookmarkDeletion() {
        pendingBookmarkDeletion = nil
    }

    private func refreshBookmarkedStopIDs() {
        guard let currentRegion = application.currentRegion else {
            bookmarkedStopIDs = []
            return
        }

        let stopBookmarks = application.userDataStore
            .findBookmarks(in: currentRegion)
            .filter { !$0.isTripBookmark }
        bookmarkedStopIDs = Set(stopBookmarks.map(\.stopID))
    }

    func deleteAllRecentStops() {
        application.userDataStore.deleteAllRecentStops()
        recentStops = []
    }

    func delete(recentStop: Stop) {
        application.userDataStore.delete(recentStop: recentStop)
        loadData()
    }

    /// Deletes through `AlarmRemover`: on the server first; see
    /// `PendingAlarmDeletions`. Tests await the returned task.
    @discardableResult
    func delete(alarm: Alarm) -> Task<Void, Never> {
        guard let task = pendingAlarmDeletions.delete(alarm, onFinish: { [weak self] in self?.loadData() }) else {
            return Task {}
        }
        alarms.removeAll { $0.url == alarm.url }
        return task
    }
}
