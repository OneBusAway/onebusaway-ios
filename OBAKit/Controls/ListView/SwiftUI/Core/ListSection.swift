//
//  ListSection.swift
//  OBAKit
//

import SwiftUI

// MARK: - ListSectionState

public enum ListSectionState {
    /// Show the section's normal content (default).
    case content
    /// Replace content with an inline loading indicator.
    case loading
    /// Replace content with an inline empty-state placeholder.
    case empty(EmptyStateConfiguration)
}

// MARK: - SectionLoadingRow

struct SectionLoadingRow: View {
    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }
}

// MARK: - SectionEmptyRow

struct SectionEmptyRow: View {
    let configuration: EmptyStateConfiguration

    var body: some View {
        VStack(spacing: 4) {
            Text(configuration.title)
                .font(.callout)
                .foregroundStyle(.secondary)

            if let body = configuration.body {
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let buttonTitle = configuration.buttonTitle,
               let action = configuration.buttonAction {
                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
    }
}

// MARK: - ListSection

public struct ListSection<Content: View>: View, Identifiable {

    // MARK: Stored Properties

    public let id: String
    private let headerKind: HeaderKind
    private let isCollapsible: Bool
    private let externalExpanded: Binding<Bool>?
    private let content: Content
    private var sectionStateOverride: ListSectionState
    private var paginationAction: (() -> Void)? = nil
    private var isLoadingMore: Bool = false

    @State private var internalExpanded: Bool = true

    private var resolvedExpanded: Binding<Bool> {
        externalExpanded ?? $internalExpanded
    }

    // MARK: Init

    public init(
        id: String,
        title: String? = nil,
        isCollapsible: Bool = false,
        isExpanded: Binding<Bool>? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.id = id
        self.headerKind = title.map { .text($0) } ?? .none
        self.isCollapsible = isCollapsible
        self.externalExpanded = isExpanded
        self.content = content()
        self.sectionStateOverride = .content
    }

    // MARK: Body

    public var body: some View {
        if isCollapsible {
            collapsableSection
        } else {
            ordinarySection
        }
    }

    // MARK: Public Methods

    public func sectionState(_ state: ListSectionState) -> ListSection<Content> {
        var copy = self
        copy.sectionStateOverride = state
        return copy
    }

    /// Appends a pagination footer to the section.
    ///
    /// The footer shows a spinner whenever it is visible. When the footer first
    /// appears and `isLoading` is `false`, `action` is called so the next page
    /// can be fetched. Pass `nil` (or omit the modifier) once there are no more
    /// pages to load.
    ///
    /// - Note: This modifier has no effect when `sectionState` is `.loading` or
    ///   `.empty`; the pagination footer is only appended in the `.content` state.
    public func loadMore(isLoading: Bool, action: @escaping () -> Void) -> ListSection<Content> {
        var copy = self
        copy.paginationAction = action
        copy.isLoadingMore = isLoading
        return copy
    }

    // MARK: Private

    private var collapsableSection: some View {
        Section {
            if resolvedExpanded.wrappedValue {
                stateContent
            }
        } header: {
            switch headerKind {
            case .none:
                CollapsibleSectionHeader(title: nil, isExpanded: resolvedExpanded)
            case .text(let title):
                CollapsibleSectionHeader(title: title, isExpanded: resolvedExpanded)
            case .custom(let header):
                header
            }
        }
    }

    @ViewBuilder
    private var ordinarySection: some View {
        switch headerKind {
        case .none:
            Section {
                stateContent
            }
        case .text(let title):
            Section(title) {
                stateContent
            }
        case .custom(let header):
            Section {
                stateContent
            } header: {
                header
            }
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch sectionStateOverride {
        case .content:
            content
            if let action = paginationAction {
                PaginationFooterRow(isLoading: isLoadingMore, onLoadMore: action)
            }
        case .loading:
            SectionLoadingRow()
        case .empty(let config):
            SectionEmptyRow(configuration: config)
        }
    }
}

// MARK: - HeaderKind

extension ListSection {
    private enum HeaderKind {
        case none
        case text(String)
        case custom(AnyView)
    }
}

// MARK: - Items Array Init

extension ListSection {
    /// Creates a section from a homogeneous array of identifiable items.
    /// Internally wraps items in a `ForEach` — no boilerplate needed at the call site.
    public init<Item: Identifiable, RowContent: View>(
        id: String,
        title: String? = nil,
        items: [Item],
        isCollapsible: Bool = false,
        isExpanded: Binding<Bool>? = nil,
        @ViewBuilder row: @escaping (Item) -> RowContent
    ) where Content == ForEach<[Item], Item.ID, RowContent> {
        self.id = id
        self.headerKind = title.map { .text($0) } ?? .none
        self.isCollapsible = isCollapsible
        self.externalExpanded = isExpanded
        self.content = ForEach(items, content: row)
        self.sectionStateOverride = .content
    }
}

// MARK: - Custom Header Init

extension ListSection {

    public init<Header: View>(
        id: String,
        isCollapsible: Bool = false,
        isExpanded: Binding<Bool>? = nil,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.id = id
        self.headerKind = .custom(AnyView(header()))
        self.isCollapsible = isCollapsible
        self.externalExpanded = isExpanded
        self.content = content()
        self.sectionStateOverride = .content
    }

}

// MARK: - CollapsibleSectionHeader

/// Tappable section header used for collapsible sections.
private struct CollapsibleSectionHeader: View {

    // MARK: Stored Properties

    let title: String?
    @Binding var isExpanded: Bool

    private var accessibilityValueString: String {
        isExpanded ? OBALoc(
            "collapsible_section_header.expanded",
            value: "Expanded",
            comment: "Accessibility value for an expanded collapsible section header."
        ) : OBALoc(
            "collapsible_section_header.collapsed",
            value: "Collapsed",
            comment: "Accessibility value for a collapsed collapsible section header."
        )
    }

    private var accessibilityHintString: String {
        isExpanded ? OBALoc(
            "collapsible_section_header.hint_collapse",
            value: "Double-tap to collapse",
            comment: "Accessibility hint for a collapsible section header that is currently expanded."
        ) : OBALoc(
            "collapsible_section_header.hint_expand",
            value: "Double-tap to expand",
            comment: "Accessibility hint for a collapsible section header that is currently collapsed."
        )
    }

    // MARK: Body

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded.toggle()
            }
        } label: {
            headerRow
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(accessibilityValueString)
        .accessibilityHint(accessibilityHintString)
    }

    // MARK: Private Views

    private var headerRow: some View {
        HStack(spacing: 4) {
            if let title {
                Text(title)
            }
            Spacer()
            chevronIcon
        }
    }

    private var chevronIcon: some View {
        Image(systemName: "chevron.down")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(isExpanded ? .zero : .degrees(-90))
            .animation(.easeInOut(duration: 0.25), value: isExpanded)
    }
}
