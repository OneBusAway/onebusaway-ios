//
//  BookmarksViewModel.swift
//  OBAWatch Watch App
//
//  Created by Prince Yadav on 31/12/25.
//

import Foundation
import SwiftUI
import Combine
import OBASharedCore

// Lightweight bookmark model for watchOS.
// This is intentionally decoupled from OBAKitCore and mirrors
// just the fields needed by the watch UI.
struct Bookmark: Identifiable, Codable, Equatable {
    let id: UUID
    let stopID: OBAStopID
    let name: String
    let routeShortName: String?
    let tripHeadsign: String?
    let stop: OBAStop?
}

@MainActor
class BookmarksViewModel: ObservableObject {
    @Published var bookmarks: [Bookmark] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Shared storage key that can be written by the iOS app via app group or
    // WatchConnectivity payloads.
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
    
    func loadBookmarks(from defaults: UserDefaults = .standard) {
        guard let data = defaults.data(forKey: storageKey) else {
            bookmarks = []
            return
        }

        do {
            let decoder = JSONDecoder()
            let decoded = try decoder.decode([Bookmark].self, from: data)
            print("Successfully decoded \(decoded.count) bookmarks.")
            bookmarks = decoded.sorted { $0.name < $1.name }
        } catch {
            print("Failed to decode bookmarks: \(error)")
            // Try to see if we can decode anything from the data to help debugging
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
                print("Raw JSON that failed to decode: \(json)")
            }
            bookmarks = []
            errorMessage = "Failed to load bookmarks."
        }
    }
    
    func refreshData() async {
        // For now, bookmarks are stored locally on the watch or provided by
        // a companion sync process on iPhone. This simply reloads from
        // shared storage. The iOS app can update the same key via an
        // app-group UserDefaults or WatchConnectivity and the watch will
        // pick it up here.
        loadBookmarks()
    }

    func addBookmark(stop: OBAStop,
                     routeShortName: String? = nil,
                     tripHeadsign: String? = nil) {
        let bookmark = Bookmark(
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
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            errorMessage = "Failed to save bookmark."
        }
    }
}

