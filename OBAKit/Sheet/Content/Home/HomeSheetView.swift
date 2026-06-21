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
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text("Search stops, routes…")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            Capsule()
                .fill(.gray.opacity(0.3))
        }
        .padding(.horizontal, 12)
        .contentShape(.rect(cornerRadius: 16))
        .onTapGesture {
            expandThenPushSearch()
        }
    }

    /// Animates the home sheet to its largest detent, then swaps content to
    /// `.search`. The two-step flow avoids the jarring small→large+swap in one
    /// frame; the user sees the sheet expand, then the search UI replace home.
    ///
    /// If the user collapses the sheet (or the route changes) before the
    /// expansion finishes, the swap is skipped.
    private func expandThenPushSearch() {
        withAnimation(.smooth(duration: 0.3)) {
            coordinator.currentDetent = AppSheetRoute.largeDetent
        } completion: {
            guard coordinator.currentRoute == .home,
                  coordinator.currentDetent == AppSheetRoute.largeDetent
            else { return }
            coordinator.push(.search)
        }
    }

}
