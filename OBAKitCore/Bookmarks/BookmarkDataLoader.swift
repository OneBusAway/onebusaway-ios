//
//  BookmarkDataLoader.swift
//  OBAKitCore
//
//  Created by Aaron Brethorst on 2/7/20.
//

import Foundation

public protocol BookmarkDataDelegate: NSObjectProtocol {
    func dataLoaderDidUpdate(_ dataLoader: BookmarkDataLoader)
}

/// Loads `[ArrivalDeparture]`s every 30 seconds for the list of provided `Bookmark`s.
public class BookmarkDataLoader: NSObject {
    private let refreshInterval = 30.0

    private var timer: Timer?

    private let application: CoreApplication

    public weak var delegate: BookmarkDataDelegate?

    public init(application: CoreApplication, delegate: BookmarkDataDelegate) {
        self.application = application
        self.delegate = delegate
    }

    public func startRefreshTimer() {
        timer?.invalidate()

        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.loadData()
        }
    }

    public func cancelUpdates() {
        timer?.invalidate()

        for op in operations {
            op.cancel()
        }
    }

    private var operations = [Operation]()

    public func loadData() {
        cancelUpdates()
        for bookmark in application.userDataStore.bookmarks {
            loadData(bookmark: bookmark)
        }
        startRefreshTimer()
    }

    private func loadData(bookmark: Bookmark) {
        guard let apiService = application.restAPIService else { return }

        let op = apiService.getArrivalsAndDeparturesForStop(id: bookmark.stopID, minutesBefore: 0, minutesAfter: 60)
        op.complete { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                print("TODO FIXME handle error! \(error)")
            case .success(let response):
                let keysAndDeps = response.list.arrivalsAndDepartures.tripKeyGroupedElements
                for (key, deps) in keysAndDeps {
                    self.tripBookmarkKeys[key] = deps
                }

                self.delegate?.dataLoaderDidUpdate(self)
            }
        }
        operations.append(op)
    }

    public func dataForKey(_ key: TripBookmarkKey) -> [ArrivalDeparture] {
        tripBookmarkKeys[key, default: []]
    }

    /// A dictionary that maps each bookmark to `ArrivalDeparture`s.
    /// This is used to update the UI when new `ArrivalDeparture` objects are loaded.
    private var tripBookmarkKeys = [TripBookmarkKey: [ArrivalDeparture]]()
}
