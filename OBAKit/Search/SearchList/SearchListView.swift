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

    /// Background for a sheet hosting a search list.
    ///
    /// Nothing where the sheet shows its Liquid Glass (`showsSheetGlass`: iOS 26,
    /// light mode): a partial-height sheet's own background is glass, which
    /// turns opaque by itself as the sheet reaches full height, and a
    /// `presentationBackground` would replace it. The cards read against the
    /// glass, as Maps' and Find My's do.
    ///
    /// Otherwise `systemGroupedBackground`. Before iOS 26, sheets default to
    /// `systemBackground`, and `insetGrouped` rows are filled with
    /// `secondarySystemGroupedBackground` — the same colour in light mode. The
    /// cards are drawn, but they're white on white, so the rows read as plain
    /// text with no list edges at all. Painting the sheet with
    /// `systemGroupedBackground` is what a grouped list normally sits on and gives
    /// the cards their contrast back. Applied to the whole sheet rather than left
    /// to the `List`'s own background so the colour runs edge to edge, instead of
    /// starting below the search field and leaving the header two-tone.
    func searchSheetBackground() -> some View {
        modifier(SearchSheetBackground())
    }
}

private struct SearchSheetBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if colorScheme.showsSheetGlass {
            content
        } else {
            content.presentationBackground(Color.searchSheetBackground)
        }
    }
}

extension Color {
    /// The search and index sheets' background when they don't show glass; see
    /// `searchSheetBackground()`. Shared with views that paint over the sheet
    /// and must match it.
    static let searchSheetBackground = Color(.systemGroupedBackground)
}

// MARK: - SearchListSectionsView

/// Shared section renderer used by both `SearchListView` and `.searchSuggestions`.
struct SearchListSectionsView: View {
    let sections: [SearchListSection]

    var body: some View {
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
}

// MARK: - SearchListContentView

private struct SearchListContentView: View {
    let sections: [SearchListSection]

    var body: some View {
        List {
            SearchListSectionsView(sections: sections)
        }
        .searchListChrome()
    }
}

// MARK: - SearchListEmptyStateView

private struct SearchListEmptyStateView: View {
    /// Scales with Dynamic Type. It used to key off `accessibilityEnabled`,
    /// which is true whenever *any* assistive tech is on and says nothing about
    /// the rider's text size.
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 64

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true) // decorative; the title below says "Search"

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
