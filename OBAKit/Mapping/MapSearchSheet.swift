//
//  MapSearchSheet.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore
import MapKit

// MARK: - ViewModel

/// Observable state shared between the SwiftUI sheet and the UIKit SearchInteractor.
@MainActor
final class MapSearchSheetViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var sections: [SearchResultSection] = []

    var onCancel: (() -> Void)?
    var onSearchTextChanged: ((String) -> Void)?
    var onSelectStop: ((Stop.ID) -> Void)?
    var onSelectMapItem: ((MKMapItem) -> Void)?
    var onPerformSearch: ((SearchRequest) -> Void)?
    var onClearRecentSearches: (() -> Void)?
    var onDismiss: (() -> Void)?
}

// MARK: - Section model

/// A flat, SwiftUI-renderable representation of one OBAListViewSection.
struct SearchResultSection: Identifiable {
    let id: String
    let title: String?
    let rows: [SearchResultRow]
}

struct SearchResultRow: Identifiable {
    let id: String
    let title: AttributedString
    let subtitle: String?
    let image: UIImage?
    let action: () -> Void
}

// MARK: - Custom detent

/// Matches the height of the search bar row — the sheet starts here, collapsed to just the search field.
private struct SearchBarDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? { 100 }
}

// MARK: - Sheet View

/// A native SwiftUI bottom sheet for the map search experience.
///
/// Starts at a small "searchBar" detent (just the search row visible) and
/// expands to medium/large — matching the Apple Maps sheet interaction model.
struct MapSearchSheet: View {
    @ObservedObject var viewModel: MapSearchSheetViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.searchText.isEmpty && viewModel.sections.isEmpty {
                    emptyStateView
                } else {
                    resultsList
                }
            }
            .navigationTitle(OBALoc(
                "search_controller.title",
                value: "Search",
                comment: "Title for the search sheet."
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.cancel) {
                        viewModel.onCancel?()
                    }
                }
            }
        }
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(OBALoc(
                "map_floating_panel.search_prompt",
                value: "Search stops, routes, addresses",
                comment: "Search bar placeholder in the map search sheet."
            ))
        )
        .onChange(of: viewModel.searchText) { _, newValue in
            viewModel.onSearchTextChanged?(newValue)
        }
        .presentationDetents([.custom(SearchBarDetent.self), .medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    // MARK: - Results List

    private var resultsList: some View {
        List {
            ForEach(viewModel.sections) { section in
                Section(header: section.title.map { Text($0) }) {
                    ForEach(section.rows) { row in
                        Button {
                            row.action()
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title)
                                        .foregroundStyle(.primary)
                                    if let subtitle = row.subtitle {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } icon: {
                                if let image = row.image {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 24, height: 24)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(OBALoc(
                "search_controller.empty_set.title",
                value: "Search",
                comment: "Title for the empty set indicator on the Search controller."
            ))
            .font(.title2.bold())
            .foregroundStyle(.primary)

            Text(OBALoc(
                "search_controller.empty_set.body",
                value: "Type in an address, route name, stop number, or vehicle here to search.",
                comment: "Body for the empty set indicator on the Search controller."
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
