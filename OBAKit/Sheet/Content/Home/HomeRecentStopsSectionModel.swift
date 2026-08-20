//
//  HomeRecentStopsSectionModel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// The home sheet's recent-stops preview.
///
/// Backed entirely by `UserDataStore`, so it costs no network requests. Recents
/// are already stored most-recently-used first, so there is nothing to sort.
@MainActor
final class HomeRecentStopsSectionModel: ObservableObject {

    @Published private(set) var stops: [Stop] = []

    private let application: Application
    private let limit: Int

    init(application: Application, limit: Int = HomeSheetSection.itemLimit) {
        self.application = application
        self.limit = limit
        reload()
    }

    /// Re-reads the store. Called on activation and on region change — a
    /// region switch changes which recents are current, and the store posts no
    /// notification for it.
    ///
    /// Guarded against a no-op write: `activate()` runs on every sheet
    /// re-appearance and the store usually hasn't changed, so an unconditional
    /// assignment would fire `objectWillChange` — and through the view model's
    /// forwarding, a whole home-sheet body evaluation — for nothing.
    func reload() {
        let reloaded = Array(
            application.userDataStore
                .recentStops(in: application.currentRegion)
                .prefix(limit)
        )
        guard reloaded != stops else { return }
        stops = reloaded
    }
}
