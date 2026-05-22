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

    /// `true` when the user has chosen to sort bookmarks by group (vs. by distance).
    @Published var sortByGroup: Bool

    // MARK: - Private

    let application: Application
    private lazy var dataLoader = BookmarkDataLoader(application: application, delegate: self)

    private enum UserDefaultsKey: String {
        case sortByGroup = "OBABookmarksController_SortBookmarksByGroup"
    }

    // MARK: - Init

    init(application: Application) {
        self.application = application
        application.userDefaults.register(defaults: [UserDefaultsKey.sortByGroup.rawValue: true])
        self.sortByGroup = application.userDefaults.bool(forKey: UserDefaultsKey.sortByGroup.rawValue)
        super.init()
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
        Task { @MainActor [weak self] in
            self?.didUpdateSubject.send()
        }
    }
}
