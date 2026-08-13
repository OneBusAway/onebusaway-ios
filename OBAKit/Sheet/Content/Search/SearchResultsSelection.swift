//
//  SearchResultsSelection.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Opening a row picked out of a disambiguation list, plus whatever failure that
/// left behind.
///
/// A separate object rather than `@State` on `SearchResultsSheetView` so the two
/// things worth pinning — the resolve/unwind/present ordering, and the fact that a
/// failed resolve is reported instead of dropped — can be asserted without a view
/// host. `SearchSheetViewModel` plays the same role for the search sheet.
@MainActor
final class SearchResultsSelection: ObservableObject {

    /// Set when `select(_:coordinator:)` could not resolve a result, so the sheet can
    /// render the failure inline rather than leaving the tapped row doing nothing.
    @Published private(set) var error: Error?

    /// The result the failure belongs to, kept so the inline error row can offer a
    /// retry instead of dead-ending the user.
    @Published private(set) var failedResult: Any?

    private let router: SearchResultRouter

    init(router: SearchResultRouter) {
        self.router = router
    }

    /// Unwinds back to home and opens `result` — the SwiftUI equivalent of the UIKit
    /// path's `exitSearchMode()`.
    ///
    /// Resolution comes first so the results sheet stays up while the request runs: a
    /// failure leaves the user on their results rather than dropping them on home, and
    /// the stacked layer isn't emptied and refilled around a network call.
    ///
    /// `popToRoot()` rather than `dismiss()` + `pop()`: two layers have to come off
    /// (the stacked results sheet and the `.search` route beneath it), and `pop()` acts
    /// on whichever layer is topmost *at the moment it runs* — racing the SwiftUI
    /// binding write that `dismiss()` triggers. `popToRoot()` clears both
    /// deterministically in one step.
    func select(_ result: Any, coordinator: SheetCoordinator<AppSheetRoute>) async {
        error = nil
        failedResult = nil

        guard let resolved = await router.resolve(result: result) else {
            // `router.lastError` is nil only for a result type `resolve` doesn't
            // handle, which is a programming error rather than anything the user did
            // — but the row still has to say *something*, or tapping it is a no-op.
            error = router.lastError ?? UnstructuredError(Self.unresolvableText)
            failedResult = result
            return
        }

        coordinator.popToRoot()
        router.present(resolved)
    }

    static let unresolvableText = OBALoc(
        "search_results_sheet.unresolvable_result",
        value: "This search result could not be opened.",
        comment: "Error shown when a tapped search result cannot be turned into something to display."
    )
}
