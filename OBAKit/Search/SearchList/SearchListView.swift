//
//  SearchListView.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 08/03/2026.
//

import SwiftUI
import OBAKitCore

// MARK: - SearchListView

struct SearchListView: View {
    @Bindable var searchInteractor: SearchInteractor

    var body: some View {
        Group {
            if searchInteractor.sections.isEmpty {
                SearchListEmptyStateView()
            } else {
                SearchListContentView(sections: searchInteractor.sections)
            }
        }
    }
}

// MARK: - SearchListContentView

private struct SearchListContentView: View {
    let sections: [SearchListSection]

    var body: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.content) { row in
                        SearchListRowView(row: row)
                    }
                } header: {
                    Text(section.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, 8, for: .scrollContent)
        .background(.clear)
    }
}

// MARK: - SearchListEmptyStateView

private struct SearchListEmptyStateView: View {
    @Environment(\.accessibilityEnabled) private var accessibilityEnabled

    private var size: CGFloat {
        accessibilityEnabled ? 96 : 64
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .resizable()
                .font(.largeTitle)
                .frame(width: size, height: size)
                .scaledToFit()
                .foregroundStyle(.secondary)

            Text(OBALoc(
                "search_controller.empty_set.title",
                value: "Search",
                comment: "Title for the empty set indicator on the Search controller."
            ))
            .font(.title)
            .bold()

            Text(OBALoc(
                "search_controller.empty_set.body",
                value: "Type in an address, route name, stop number, or vehicle here to search.",
                comment: "Body for the empty set indicator on the Search controller."
            ))
            .multilineTextAlignment(.center)
            .padding(.horizontal)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 48)
    }
}

#Preview {
    SearchListEmptyStateView()
        .environment(\.accessibilityEnabled, false)
}
