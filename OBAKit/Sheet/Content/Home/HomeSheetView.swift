//
//  HomeSheetView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

struct HomeSheetView: View {
    @StateObject private var viewModel: HomeSheetViewModel
    @EnvironmentObject var coordinator: SheetCoordinator<AppSheetRoute>

    init(viewModel: @autoclosure @escaping () -> HomeSheetViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                searchBarRow
                    .padding(.top, 16)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    // MARK: - Search Bar

    private var searchBarRow: some View {
        // `Button` (rather than `.onTapGesture` on a container) so VoiceOver
        // and Switch Control see action semantics — the row is announced as a
        // button and reachable via accessibility actions. `.buttonStyle(.plain)`
        // keeps the search-pill appearance.
        Button(action: expandSheet) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(OBALoc(
                    "home_sheet.search_bar.placeholder",
                    value: "Search stops, routes…",
                    comment: "Placeholder text inside the search bar on the home sheet."
                ))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                Capsule()
                    .fill(Color(.tertiarySystemFill))
            }
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }

    /// Animates the home sheet to its largest detent.
    ///
    /// TODO: Push `.search` once `AppSheetViewFactory` has a real view for it
    /// — the two-step expand-then-push flow lives in git history. Pushing
    /// today would land on `unimplementedView(for:)` and trip the debug
    /// assertion that guards stray routes.
    private func expandSheet() {
        withAnimation(.smooth(duration: 0.3)) {
            coordinator.currentDetent = AppSheetRoute.largeDetent
        }
    }

}
