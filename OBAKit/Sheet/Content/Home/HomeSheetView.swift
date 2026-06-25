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
        // Disabled until the `.search` route has a real view with a back
        // affordance — `expandSheet()` would otherwise animate to the largest
        // detent and strand the user there (the route is base-layer with
        // `isDismissDisabled: true`). Surfaced as "Coming soon" so the only
        // interactive control on the home sheet doesn't read as a dead tap.
        //
        // `Button` (rather than `.onTapGesture` on a container) so VoiceOver
        // and Switch Control see action semantics — the row is announced as a
        // button and reachable via accessibility actions. `.buttonStyle(.plain)`
        // keeps the search-pill appearance.
        Button(action: {}) {
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
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(true)
        .padding(.horizontal, 12)
    }

}
