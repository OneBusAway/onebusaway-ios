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
        Button {
            coordinator.push(.search)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(viewModel.searchPlaceholder)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background { Capsule().fill(Color(.tertiarySystemFill)) }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }

}
