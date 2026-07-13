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
    let onPresentTrip: (ArrivalDeparture) -> Void

    init(application: Application, onPresentTrip: @escaping (ArrivalDeparture) -> Void) {
        self.application = application
        self.onPresentTrip = onPresentTrip
    }

    // MARK: - Dispatcher

    @ViewBuilder
    func view(for route: AppSheetRoute) -> some View {
        switch route {
        case .home:
            homeView()

        case .more:
            moreView()

        // Wiring a push for one of these routes before its view exists will
        // trip the debug assertion in `unimplementedView(for:)` — register the
        // view here before reaching for `SheetCoordinator.push(...)`.
        //
        // TODO: `.search` is base-layer and has `isDismissDisabled: true`
        // — its real view needs to wire up an explicit back affordance
        // (the home sheet only knows how to push, not pop), otherwise the
        // route is unreachable once entered.
        case .search, .nearbyAll, .recentStopsAll, .bookmarksAll,
             .stopDetails, .tripPlanner, .tripDetails, .transitAlert, .settings:
            unimplementedView(for: route)

        case .routePicker:
            routePickerView()

        case .currentTrip(let route):
            currentTripView(route: route)
        }
    }

    // MARK: - Per-route view builders

    func homeView() -> HomeSheetView {
        HomeSheetView(viewModel: HomeSheetViewModel())
    }

    /// Bridges `AppSheetRoute.more` to the existing UIKit `MoreViewController`
    /// via `MoreSheetHost`. Swap this branch's return type once the SwiftUI
    /// `MoreView` lands.
    func moreView() -> MoreSheetHost {
        MoreSheetHost(application: application)
    }

    func routePickerView() -> RoutePickerView {
        RoutePickerView(viewModel: RoutePickerViewModel(application: self.application))
    }

    private func currentTripView(route: Route) -> CurrentTripView {
        CurrentTripView(
            viewModel: CurrentTripViewModel(application: self.application, route: route),
            feedback: DataLoadFeedbackGenerator(application: self.application),
            formatters: self.application.formatters,
            onPresentTrip: onPresentTrip
        )
    }

    /// Placeholder until each route gets its own real view. In debug builds we
    /// surface a visible label and fire an assertion so a stray `push(...)`
    /// during development can't silently render a blank sheet. In release we
    /// log and render a visible "coming soon" message — preferable to
    /// `EmptyView()`, which would leave an experimental tester staring at a
    /// blank sheet with no breadcrumb in the UI.
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
        // swiftlint:disable:next redundant_discardable_let
        let _ = Logger.error("AppSheetRoute.\(route.id) pushed but no view is registered — rendering placeholder.")
        // Embed `route.id` in the visible copy so an experimental-flag tester
        // who hits this in the wild has something concrete to report back —
        // the `Logger.error` line above is invisible to them.
        VStack(spacing: 4) {
            Text(OBALoc(
                "app_sheet.unimplemented_route.placeholder",
                value: "This screen is coming soon.",
                comment: "Placeholder shown in release builds when a sheet route is pushed but has no view registered."
            ))
            .font(.headline)
            .foregroundStyle(.secondary)
            Text(route.id)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
#endif
    }
}
