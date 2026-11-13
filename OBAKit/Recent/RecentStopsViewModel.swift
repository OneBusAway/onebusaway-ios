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
    /// Alarms being deleted on the server. Off the list at once, so a swipe's
    /// delete animation matches the data, and kept off it by `loadData()` until
    /// the server answers: the store drops its copy only after that.
    private var pendingAlarmDeletions = Set<URL>()
    private var cancellables = Set<AnyCancellable>()

    init(application: Application) {
        self.application = application

        NotificationCenter.default.publisher(for: .bookmarksDidChange, object: application.userDataStore)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshBookmarkedStopIDs()
            }
            .store(in: &cancellables)

        refreshBookmarkedStopIDs()
    }

    func loadData() {
        application.userDataStore.deleteExpiredAlarms()
        alarms = application.userDataStore.alarms.filter { !pendingAlarmDeletions.contains($0.url) }
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
        recentStops = application.userDataStore.recentStops(in: currentRegion)
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

    /// Deletes through `AlarmRemover`: on the server first. The row leaves the list
    /// straight away; if the server keeps the alarm, it comes back in its place,
    /// where the rider can see it and try again.
    @discardableResult
    func delete(alarm: Alarm) -> Task<Void, Never> {
        // Already on its way: a second request would race the first.
        guard pendingAlarmDeletions.insert(alarm.url).inserted else { return Task {} }
        alarms.removeAll { $0.url == alarm.url }

        // Capture the remover directly: if the VM is deallocated mid-delete (common when
        // the user pops the view right after tapping delete), [weak self] would abort
        // the DELETE before it ran, leaving the alarm live on the Obaco server.
        // The returned Task is `@discardableResult` for the call site, but tests can
        // await it to assert on remote-side behaviour.
        let remover = AlarmRemover(application: application)
        let application = application
        return Task { [weak self] in
            do {
                try await remover.remove(alarm)
                self?.finishDeleting(alarm)
            } catch {
                Logger.error("Failed to delete alarm: \(error.localizedDescription)")
                self?.finishDeleting(alarm)
                await application.displayError(error)
            }
        }
    }

    /// Done either way: reloading lists the alarm again if the store still has it,
    /// in the store's order, which is where it was.
    private func finishDeleting(_ alarm: Alarm) {
        pendingAlarmDeletions.remove(alarm.url)
        loadData()
    }
}
