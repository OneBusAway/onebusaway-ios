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
    var searchInteractor: SearchInteractor

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

// MARK: - Shared list chrome

extension View {
    /// The list treatment shared by every search surface: inset-grouped cards on no
    /// background of the list's own.
    ///
    /// Pairs with `searchSheetBackground()` on the enclosing sheet — hiding the
    /// list's background only works if something behind it supplies the contrast the
    /// cards need.
    func searchListChrome() -> some View {
        self
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, 8, for: .scrollContent)
            .background(.clear)
    }

    /// Grouped background for a sheet hosting a search list.
    ///
    /// Sheets default to `systemBackground`, and `insetGrouped` rows are filled with
    /// `secondarySystemGroupedBackground` — the same colour in light mode. The cards
    /// are drawn, but they're white on white, so the rows read as plain text with no
    /// list edges at all. Painting the sheet with `systemGroupedBackground` is what
    /// a grouped list normally sits on and gives the cards their contrast back.
    ///
    /// Applied to the whole sheet rather than left to the `List`'s own background so
    /// the colour runs edge to edge, instead of starting below the search field and
    /// leaving the header two-tone.
    func searchSheetBackground() -> some View {
        presentationBackground(Color(.systemGroupedBackground))
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
        .searchListChrome()
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
