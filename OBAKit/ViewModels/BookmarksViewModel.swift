//
//  BookmarksViewModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Combine
import OBAKitCore

/// Shared ViewModel for the Bookmarks tab.
///
/// Consumed by `BookmarksViewController` (UIKit, via Combine `sink`) and by
/// future `BookmarksSheetView` (SwiftUI, via `@StateObject`).
/// Contains no UIKit imports.
///
/// Subclasses NSObject to adopt the `BookmarkDataDelegate` protocol.
@MainActor
class BookmarksViewModel: NSObject, ObservableObject, BookmarkDataDelegate {

    // MARK: - Published State

    /// Fires each time arrival data is refreshed. Observers call `arrivalDepartures(for:)` to rebuild their list.
    var didUpdate: AnyPublisher<Void, Never> {
        didUpdateSubject.eraseToAnyPublisher()
    }
    private let didUpdateSubject = PassthroughSubject<Void, Never>()

    /// `true` while the data loader has any per-bookmark fetch in flight.
    /// Drives spinner UI in consumers; transitions are reported by the loader
    /// once per batch boundary (not once per individual fetch).
    @Published private(set) var isLoading: Bool = false

    /// `true` when the user has chosen to sort bookmarks by group (vs. by distance).
    @Published var sortByGroup: Bool

    /// Whether the most-recently-completed refresh batch had any failed fetch.
    /// Read by the VC when `isLoading` transitions to `false` to pick success vs.
    /// failure haptic feedback. Not `@Published` — it's a direct read, not an observed sink.
    private(set) var lastRefreshHadError: Bool = false

    // MARK: - Private

    private let application: Application
    private var dataLoader: BookmarkDataLoader!

    private enum UserDefaultsKey: String {
        case sortByGroup = "OBABookmarksController_SortBookmarksByGroup"
    }

    // MARK: - Init

    init(application: Application) {
        self.application = application
        application.userDefaults.register(defaults: [UserDefaultsKey.sortByGroup.rawValue: true])
        self.sortByGroup = application.userDefaults.bool(forKey: UserDefaultsKey.sortByGroup.rawValue)
        super.init()
        self.dataLoader = BookmarkDataLoader(application: application, delegate: self)
    }

    deinit {
        dataLoader?.cancelUpdates()
    }

    // MARK: - Lifecycle

    /// Call from `viewDidLoad` / `.task`.
    func start() {
        dataLoader.loadData()
    }

    /// Call from `viewWillDisappear` / `.onDisappear`.
    func deactivate() {
        dataLoader.cancelUpdates()
    }

    // MARK: - Refresh

    func refresh() {
        dataLoader.loadData()
    }

    // MARK: - Sort

    func updateSortType(byGroup: Bool) {
        sortByGroup = byGroup
        application.userDefaults.setValue(byGroup, forKey: UserDefaultsKey.sortByGroup.rawValue)
    }

    // MARK: - Data Access

    /// Returns arrival/departure data for the given bookmark's trip key.
    func arrivalDepartures(for bookmark: Bookmark) -> [ArrivalDeparture] {
        guard let key = TripBookmarkKey(bookmark: bookmark) else { return [] }
        return dataLoader.dataForKey(key)
    }

    // MARK: - Bookmark Management

    func deleteBookmark(_ bookmark: Bookmark) {
        application.userDataStore.delete(bookmark: bookmark)
    }

    // MARK: - BookmarkDataDelegate

    nonisolated func dataLoaderDidUpdate(_ dataLoader: BookmarkDataLoader) {
        // BookmarkDataLoader dispatches this callback inside `await MainActor.run`, so
        // we're already on the main actor. `assumeIsolated` confirms that without the
        // round-trip Task hop. Traps loudly if the loader's contract ever changes.
        MainActor.assumeIsolated {
            didUpdateSubject.send()
        }
    }

    nonisolated func dataLoader(_ dataLoader: BookmarkDataLoader, isLoadingChanged isLoading: Bool) {
        MainActor.assumeIsolated {
            // Capture the batch's error state before flipping `isLoading`, so the VC's
            // `$isLoading` sink reads an up-to-date `lastRefreshHadError` when it fires.
            if !isLoading {
                self.lastRefreshHadError = dataLoader.lastBatchHadError
            }
            self.isLoading = isLoading
        }
    }
}
