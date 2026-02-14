//
//  BookmarksViewModel.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import Foundation
import SwiftUI
import Combine
import OBAKitCore

@MainActor
class BookmarksViewModel: ObservableObject {
    @Published var bookmarks: [WatchBookmark] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Shared storage key that can be written by the iOS app via app group.
    private let storageKey = "watch.bookmarks"
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadBookmarks()

        // Listen for external updates from the sync manager (iPhone → watch).
        NotificationCenter.default.publisher(for: BookmarksSyncManager.bookmarksUpdatedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadBookmarks()
            }
            .store(in: &cancellables)
    }
    
    func loadBookmarks(from defaults: UserDefaults = WatchAppState.userDefaults) {
        guard let data = defaults.data(forKey: storageKey) else {
            bookmarks = []
            return
        }

        do {
            let decoder = JSONDecoder()
            let decoded = try decoder.decode([WatchBookmark].self, from: data)
            bookmarks = decoded.sorted { $0.name < $1.name }
        } catch {
            bookmarks = []
            errorMessage = "Failed to load bookmarks."
        }
    }
    
    func refreshData() async {
        // For now, bookmarks are stored locally on the watch or provided by
        // a companion sync process on iPhone. This simply reloads from
        // shared storage. The iOS app can update the same key via an
        // app-group UserDefaults and the watch will pick it up here.
        loadBookmarks()
    }

    func addBookmark(stop: OBAStop,
                     routeShortName: String? = nil,
                     tripHeadsign: String? = nil) {
        let bookmark = WatchBookmark(
            id: UUID(),
            stopID: stop.id,
            name: stop.name,
            routeShortName: routeShortName,
            tripHeadsign: tripHeadsign,
            stop: stop
        )

        var current = bookmarks
        current.removeAll { $0.stopID == bookmark.stopID }
        current.append(bookmark)
        bookmarks = current.sorted { $0.name < $1.name }

        do {
            let data = try JSONEncoder().encode(bookmarks)
            WatchAppState.userDefaults.set(data, forKey: storageKey)
        } catch {
            errorMessage = "Failed to save bookmark."
        }
    }
}

