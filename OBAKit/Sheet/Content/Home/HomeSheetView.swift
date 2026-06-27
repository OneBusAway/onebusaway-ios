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
        // Non-interactive while the `.search` route lacks a real view with a
        // back affordance — a tap would otherwise animate to the largest detent
        // and strand the user there (the route is base-layer with
        // `isDismissDisabled: true`). Rendered as an `HStack` (not a disabled
        // `Button`) so the shape communicates "not actionable yet" honestly to
        // both readers and assistive tech — VoiceOver announces it as static
        // text rather than a disabled button.
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text(OBALoc(
                "home_sheet.search_bar.coming_soon",
                value: "Search coming soon",
                comment: "Placeholder text inside the disabled search bar on the home sheet, shown while search is unimplemented."
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
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }

}
