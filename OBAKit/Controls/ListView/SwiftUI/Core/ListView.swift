//
//  ListView.swift
//  OBAKit
//

import SwiftUI

public struct ListView<Content: View, Style: ListStyle, Item: Identifiable, RowContent: View>: View {

    private let content: Content?

    private var sectionedContent: Bool = true

    private let listStyle: Style

    private var items: [Item]
    private var rowContent: ((Item) -> RowContent)?
    private var isLoadingMore: Bool = false
    private var onLoadMore: (() -> Void)? = nil

    /// Creates a sectioned list using a `@ViewBuilder` closure of `ListSection` views.
    public init(listStyle: Style = .insetGrouped, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.sectionedContent = true
        self.listStyle = listStyle
        self.items = []
        self.rowContent = nil
    }

    /// Creates a flat list from a homogeneous array of identifiable items.
    ///
    /// - Parameters:
    ///   - items: The data to display.
    ///   - listStyle: The SwiftUI list style to apply.
    ///   - isLoadingMore: Pass `true` while a page fetch is in-flight; keeps the
    ///     footer spinner visible and suppresses duplicate `onLoadMore` calls.
    ///   - onLoadMore: Called when the pagination footer scrolls into view and
    ///     `isLoadingMore` is `false`. Pass `nil` (default) to disable pagination.
    ///   - row: A view builder that maps each item to a row view.
    public init(
        items: [Item],
        listStyle: Style = .insetGrouped,
        isLoadingMore: Bool = false,
        onLoadMore: (() -> Void)? = nil,
        @ViewBuilder row: @escaping (Item) -> RowContent
    ) {
        self.sectionedContent = false
        self.listStyle = listStyle
        self.content = nil
        self.rowContent = row
        self.items = items
        self.isLoadingMore = isLoadingMore
        self.onLoadMore = onLoadMore
    }

    // MARK: Body

    @ViewBuilder
    public var body: some View {
        if sectionedContent {
            List {
                content
            }
            .listStyle(listStyle)
        } else {
            List {
                ForEach(items, id: \.id) { item in
                    rowContent?(item)
                }
                if !items.isEmpty, let action = onLoadMore {
                    PaginationFooterRow(isLoading: isLoadingMore, onLoadMore: action)
                }
            }
            .listStyle(listStyle)
        }
    }

}
