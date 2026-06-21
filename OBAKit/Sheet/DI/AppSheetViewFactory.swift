//
//  AppSheetViewFactory.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

// MARK: - AppSheetViewFactory

/// The single DI seam for the SwiftUI sheet system.
///
/// The `view(for:)` dispatcher provides compiler-enforced exhaustiveness for routing call sites.
///
/// Sheet views own their VM via `@StateObject` + `@autoclosure`, so
/// per-route view builders look eager but are evaluated lazily — SwiftUI
/// invokes the underlying VM builder exactly once per view identity.
@MainActor
final class AppSheetViewFactory: ObservableObject {

    let application: Application

    init(application: Application) {
        self.application = application
    }

    // MARK: - Dispatcher

    @ViewBuilder
    func view(for route: AppSheetRoute) -> some View {
        switch route {
        case .home:
            homeView()
        case .search, .nearbyAll, .recentStopsAll, .bookmarksAll,
             .stopDetails, .tripPlanner, .tripDetails, .routePicker,
             .currentTrip, .transitAlert, .more, .settings:
            EmptyView()
        }
    }
    // MARK: - Per-route view builders

    func homeView() -> HomeSheetView {
        HomeSheetView(viewModel: HomeSheetViewModel())
    }

}
