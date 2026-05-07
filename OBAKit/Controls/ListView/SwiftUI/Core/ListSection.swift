//
//  ListSection.swift
//  OBAKit
//

import SwiftUI

// MARK: - ListSectionState

/// The display state of an individual `ListSection`.
///
/// Apply via `.sectionState(_:)` on a `ListSection`:
///
///     ListSection(id: "stops", title: "Nearby Stops", items: stops) { stop in
///         ListSubtitleRow(title: stop.name, subtitle: stop.distance)
///     }
///     .sectionState(viewModel.stopsState)
///
public enum ListSectionState {
    /// Show the section's normal content (default).
    case content
    /// Replace content with an inline loading indicator.
    case loading
    /// Replace content with a single informational text row.
    case empty(String)
}

// MARK: - SectionLoadingRow

struct SectionLoadingRow: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - SectionEmptyRow

struct SectionEmptyRow: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }
}

// MARK: - ListSection

/// A section container for use inside `ListView`.
///
/// Renders as a native `SwiftUI.Section`, supporting optional headers and collapse/expand
/// behavior. Three initialization patterns are supported:
///
/// **ViewBuilder block** — full flexibility for mixed row types:
///
///     ListSection(id: "routes", title: "Routes") {
///         ListRow(title: "Route 5")
///         ListRow(title: "Route 7")
///     }
///
/// **Items array** — concise syntax for homogeneous sections:
///
///     ListSection(id: "stops", title: "Nearby Stops", items: stops) { stop in
///         ListSubtitleRow(title: stop.name, subtitle: stop.distance)
///     }
///
/// **Custom header** — full control over the section header view:
///
///     ListSection(id: "alerts") {
///         HStack {
///             Image(systemName: "bell.fill").foregroundStyle(.orange)
///             Text("Service Alerts").font(.headline)
///         }
///     } content: {
///         ForEach(alerts) { ListRow(title: $0.summary) }
///     }
///
/// **Collapsible sections** manage their own expanded state by default. Pass an external
/// `Binding<Bool>` to control state from outside (e.g., `@AppStorage`-backed persistence):
///
///     // Self-managed state (default)
///     ListSection(id: "past", title: "Past Arrivals", isCollapsible: true) { ... }
///
///     // Externally controlled state
///     ListSection(id: "past", title: "Past Arrivals", isCollapsible: true, isExpanded: $isPastExpanded) { ... }
///
/// **Per-section state** — replace content with a loading or empty placeholder:
///
///     ListSection(id: "stops", title: "Stops", items: stops) { ... }
///         .sectionState(viewModel.stopsState)
///
public struct ListSection<Content: View>: View, Identifiable {

    // MARK: Stored Properties

    public let id: String
    private let headerKind: HeaderKind
    private let isCollapsible: Bool
    private let externalExpanded: Binding<Bool>?
    private let content: Content
    private var sectionStateOverride: ListSectionState

    @State private var internalExpanded: Bool = true

    // MARK: Init

    /// Creates a section with a text title and a `@ViewBuilder` content block.
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
        self._internalExpanded = State(initialValue: true)
    }

    // MARK: Body

    public var body: some View {
        if isCollapsible {
            Section {
                if resolvedExpanded.wrappedValue {
                    stateContent
                }
            } header: {
                switch headerKind {
                case .none:
                    CollapsibleSectionHeader(title: nil, isExpanded: resolvedExpanded)
                case .text(let t):
                    CollapsibleSectionHeader(title: t, isExpanded: resolvedExpanded)
                case .custom(let h):
                    h
                }
            }
        } else {
            switch headerKind {
            case .none:
                Section { stateContent }
            case .text(let t):
                Section(t) { stateContent }
            case .custom(let h):
                Section { stateContent } header: { h }
            }
        }
    }

    // MARK: Public Methods

    /// Returns a copy of this section with the given per-section state applied.
    ///
    ///     ListSection(id: "stops", title: "Stops", items: stops) { stop in
    ///         ListSubtitleRow(title: stop.name, subtitle: stop.distance)
    ///     }
    ///     .sectionState(viewModel.stopsState)
    ///
    public func sectionState(_ state: ListSectionState) -> ListSection<Content> {
        var copy = self
        copy.sectionStateOverride = state
        return copy
    }

    // MARK: Private

    private var resolvedExpanded: Binding<Bool> {
        externalExpanded ?? $internalExpanded
    }

    @ViewBuilder
    private var stateContent: some View {
        switch sectionStateOverride {
        case .content:
            content
        case .loading:
            SectionLoadingRow()
        case .empty(let message):
            SectionEmptyRow(message: message)
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
        self._internalExpanded = State(initialValue: true)
    }
}

// MARK: - No-Content Init (State-Only)

extension ListSection where Content == EmptyView {
    /// Creates a section with no static content.
    ///
    /// Intended for sections whose content is entirely driven by `.sectionState(_:)`:
    ///
    ///     ListSection(id: "stops", title: "Nearby Stops")
    ///         .sectionState(viewModel.stopsState)
    ///
    public init(
        id: String,
        title: String? = nil,
        isCollapsible: Bool = false,
        isExpanded: Binding<Bool>? = nil
    ) {
        self.id = id
        self.headerKind = title.map { .text($0) } ?? .none
        self.isCollapsible = isCollapsible
        self.externalExpanded = isExpanded
        self.content = EmptyView()
        self.sectionStateOverride = .content
        self._internalExpanded = State(initialValue: true)
    }
}

// MARK: - Custom Header Init

extension ListSection {
    /// Creates a section with a fully custom header view.
    ///
    ///     ListSection(id: "alerts") {
    ///         HStack {
    ///             Image(systemName: "bell.fill").foregroundStyle(.orange)
    ///             Text("Service Alerts").font(.headline)
    ///         }
    ///     } content: {
    ///         ForEach(alerts) { ListRow(title: $0.summary) }
    ///     }
    ///
    /// - Note: Custom header sections do not receive the built-in collapsible chevron.
    ///   If you need collapsible behavior with a custom header, manage the disclosure
    ///   state within the header view itself and pass `isCollapsible: true`.
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
        self._internalExpanded = State(initialValue: true)
    }
}

// MARK: - CollapsibleSectionHeader

/// Tappable section header used for collapsible sections.
///
/// Uses a custom button + animated chevron instead of `Section(isExpanded:)` so that
/// collapse/expand works with any `List` style, not just `.sidebar`.
private struct CollapsibleSectionHeader: View {

    // MARK: Stored Properties

    let title: String?
    @Binding var isExpanded: Bool

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

// MARK: - Previews

private struct PreviewStop: Identifiable {
    let id: String
    let name: String
    let distance: String
}

#Preview("Static content") {
    List {
        ListSection(id: "a", title: "Routes") {
            ListRow(title: "Route 5")
            ListRow(title: "Route 7")
            ListRow(title: "Route 43")
        }
        ListSection(id: "b", title: "Alerts") {
            ListSubtitleRow(title: "Delays on Route 5", subtitle: "Effective until 6pm")
        }
    }
}

#Preview("Items array") {
    let stops = [
        PreviewStop(id: "1", name: "University District", distance: "0.1 mi"),
        PreviewStop(id: "2", name: "Capitol Hill", distance: "0.4 mi"),
        PreviewStop(id: "3", name: "First Hill", distance: "0.7 mi")
    ]

    List {
        ListSection(id: "stops", title: "Nearby Stops", items: stops) { stop in
            ListSubtitleRow(title: stop.name, subtitle: stop.distance)
        }
    }
}

#Preview("Custom header") {
    List {
        ListSection(id: "alerts") {
            HStack(spacing: 6) {
                Image(systemName: "bell.fill")
                    .foregroundStyle(.orange)
                Text("Service Alerts")
                    .font(.headline)
            }
        } content: {
            ListRow(title: "Delays on Route 5")
            ListRow(title: "Detour on Route 7")
        }
    }
}

#Preview("Collapsible (self-managed)") {
    List {
        ListSection(id: "past", title: "Past Arrivals", isCollapsible: true) {
            ListRow(title: "Route 5 – 3 min ago")
            ListRow(title: "Route 7 – 12 min ago")
        }
        ListSection(id: "upcoming", title: "Upcoming", isCollapsible: true) {
            ListRow(title: "Route 5 – in 4 min")
            ListRow(title: "Route 7 – in 9 min")
        }
    }
    .listStyle(.insetGrouped)
}

#Preview("Collapsible (external binding)") {
    struct Wrapper: View {
        @State private var pastExpanded = true
        var body: some View {
            List {
                ListSection(id: "past", title: "Past Arrivals", isCollapsible: true, isExpanded: $pastExpanded) {
                    ListRow(title: "Route 5 – 3 min ago")
                    ListRow(title: "Route 7 – 12 min ago")
                }
            }
            .listStyle(.insetGrouped)
        }
    }
    return Wrapper()
}

#Preview("Section state") {
    List {
        ListSection(id: "loading", title: "Loading Section")
            .sectionState(.loading)
        ListSection(id: "empty", title: "Empty Section")
            .sectionState(.empty("No stops nearby"))
        ListSection(id: "content", title: "Content Section") {
            ListRow(title: "Normal row")
        }
        .sectionState(.content)
    }
}
