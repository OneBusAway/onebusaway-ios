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
final class AppSheetViewFactory {

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
        // TODO: `.search` is base-layer and has `isDismissDisabled: true`
        // — its real view needs to wire up an explicit back affordance
        // (the home sheet only knows how to push, not pop), otherwise the
        // route is unreachable once entered.
        case .search, .nearbyAll, .recentStopsAll, .bookmarksAll,
             .stopDetails, .tripPlanner, .tripDetails, .routePicker,
             .currentTrip, .transitAlert, .more, .settings:
            unimplementedView(for: route)
        }
    }

    // MARK: - Per-route view builders

    func homeView() -> HomeSheetView {
        HomeSheetView(viewModel: HomeSheetViewModel())
    }

    /// Placeholder until each route gets its own real view. In debug builds we
    /// surface a visible label and fire an assertion so a stray `push(...)`
    /// during development can't silently render a blank sheet.
    @ViewBuilder
    private func unimplementedView(for route: AppSheetRoute) -> some View {
        #if DEBUG
        // `let _` (not `_ =`) so SwiftUI's @ViewBuilder treats this as a
        // declaration rather than an expression statement — the latter fails
        // to build because `Void` doesn't conform to `View`.
        // swiftlint:disable:next redundant_discardable_let
        let _ = assertionFailure("AppSheetRoute.\(route.id) has no view registered yet.")
        Text("Unimplemented route: \(route.id)")
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding()
        #else
        EmptyView()
        #endif
    }
}
