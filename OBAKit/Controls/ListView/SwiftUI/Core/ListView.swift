//
//  ListView.swift
//  OBAKit
//

import SwiftUI

// MARK: - ListViewRenderingMode

/// Controls how a `ListView` renders its content.
///
/// Apply via `.listViewStyle(_:)` on any view:
///
///     ListView { ... }
///         .listViewStyle(.plain)
///
///     ListView(items: stops) { ListRow(title: $0.name) }
///         .listViewStyle(.lazyVStack)
///
public enum ListViewRenderingMode {
    /// Native `List` with `.insetGrouped` style (default).
    case insetGrouped
    /// Native `List` with `.plain` style.
    case plain
    /// Embeds content in a `ScrollView + LazyVStack` — no `List` chrome,
    /// maximum performance for very large item counts.
    case lazyVStack
}

private struct ListViewRenderingModeKey: EnvironmentKey {
    static let defaultValue: ListViewRenderingMode = .insetGrouped
}

extension EnvironmentValues {
    var listViewRenderingMode: ListViewRenderingMode {
        get { self[ListViewRenderingModeKey.self] }
        set { self[ListViewRenderingModeKey.self] = newValue }
    }
}

extension View {
    /// Sets the rendering mode for any `ListView` in the descendant view hierarchy.
    public func listViewStyle(_ mode: ListViewRenderingMode) -> some View {
        environment(\.listViewRenderingMode, mode)
    }
}

// MARK: - ListView

/// A SwiftUI-first list view that replaces `OBAListView` for new features.
///
/// ## Flat (homogeneous) usage
///
///     ListView(items: routes) { route in
///         ListSubtitleRow(title: route.shortName, subtitle: route.agency.name)
///             .swipeActions {
///                 Button("Delete", role: .destructive) { delete(route) }
///             }
///     }
///     .listState(viewModel.loadingState)
///
/// ## Sectioned (heterogeneous) usage
///
///     ListView {
///         ListSection(id: "alerts", title: "Alerts") {
///             ForEach(alerts) { alert in
///                 ListRow(title: alert.summary)
///             }
///         }
///         ListSection(id: "stops", title: "Nearby Stops", items: stops) { stop in
///             ListSubtitleRow(title: stop.name, subtitle: stop.distance)
///         }
///         ListSection(id: "past", title: "Past Arrivals", isCollapsible: true) {
///             ForEach(pastArrivals) { arrival in
///                 ListRow(title: arrival.routeName)
///             }
///         }
///     }
///     .listState(.empty(.standard(title: "No stops found")))
///
/// ## State management
///
/// Apply `.listState(_:)` to overlay a loading spinner or empty state:
///
///     ListView { ... }
///         .listState(.loading)
///         .listState(.empty(.error(error)))
///         .listState(.content)   // default — shows the list
///
/// ## Actions (native SwiftUI)
///
/// Actions are attached at the `ForEach` call site using standard SwiftUI modifiers.
/// Applying `.swipeActions` inside a `ForEach` body is the correct position:
///
///     ForEach(items) { item in
///         ListRow(title: item.name)
///             .swipeActions(edge: .trailing) {
///                 Button("Delete", role: .destructive) { delete(item) }
///                 Button("Bookmark") { bookmark(item) }.tint(.orange)
///             }
///             .contextMenu {
///                 Button("Share") { share(item) }
///             }
///     }
///
public struct ListView<Content: View>: View {

    // MARK: Stored Properties

    private let content: Content

    // MARK: Environment

    @Environment(\.listViewRenderingMode) private var renderingMode

    // MARK: Init

    /// Creates a sectioned list using a `@ViewBuilder` closure of `ListSection` views.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    // MARK: Body

    @ViewBuilder
    public var body: some View {
        switch renderingMode {
        case .insetGrouped:
            List { content }.listStyle(.insetGrouped)
        case .plain:
            List { content }.listStyle(.plain)
        case .lazyVStack:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    content
                }
            }
        }
    }
}

// MARK: - Flat Init

extension ListView {
    /// Creates a flat list from a homogeneous array of `Identifiable` items.
    ///
    /// All items are rendered as direct list cells with no section header. For sectioned
    /// layouts use the `@ViewBuilder` init with `ListSection` containers.
    public init<Item: Identifiable, RowContent: View>(
        items: [Item],
        @ViewBuilder row: @escaping (Item) -> RowContent
    ) where Content == ForEach<[Item], Item.ID, RowContent> {
        self.content = ForEach(items, content: row)
    }
}

// MARK: - Previews

private struct PreviewRoute: Identifiable {
    let id: String
    let name: String
    let agency: String
}

private struct PreviewStop: Identifiable {
    let id: String
    let name: String
    let distance: String
}

#Preview("Flat list") {
    let routes = [
        PreviewRoute(id: "5", name: "Route 5", agency: "King County Metro"),
        PreviewRoute(id: "7", name: "Route 7", agency: "King County Metro"),
        PreviewRoute(id: "43", name: "Route 43", agency: "King County Metro")
    ]

    ListView(items: routes) { route in
        ListSubtitleRow(title: route.name, subtitle: route.agency)
    }
}

#Preview("Sectioned list") {
    let stops = [
        PreviewStop(id: "1", name: "University District", distance: "0.1 mi"),
        PreviewStop(id: "2", name: "Capitol Hill", distance: "0.4 mi")
    ]
    let routes = [
        PreviewRoute(id: "5", name: "Route 5", agency: "King County Metro"),
        PreviewRoute(id: "7", name: "Route 7", agency: "King County Metro")
    ]

    ListView {
        ListSection(id: "stops", title: "Nearby Stops", items: stops) { stop in
            ListSubtitleRow(title: stop.name, subtitle: stop.distance)
        }
        ListSection(id: "routes", title: "Routes", items: routes) { route in
            ListSubtitleRow(title: route.name, subtitle: route.agency)
        }
        ListSection(id: "past", title: "Past Arrivals", isCollapsible: true) {
            ListRow(title: "Route 5 – 3 min ago")
            ListRow(title: "Route 7 – 12 min ago")
        }
    }
    .listStyle(.insetGrouped)
}

#Preview("Empty state") {
    ListView(items: [PreviewStop]()) { _ in
        ListRow(title: "")
    }
    .listState(.empty(.standard(
        title: "No Stops Nearby",
        body: "Move the map or search for a stop.",
        image: Image(systemName: "mappin.slash")
    )))
}

#Preview("Loading state") {
    ListView(items: [PreviewStop]()) { _ in
        ListRow(title: "")
    }
    .listState(.loading)
}

#Preview("LazyVStack rendering") {
    let routes = [
        PreviewRoute(id: "5", name: "Route 5", agency: "King County Metro"),
        PreviewRoute(id: "7", name: "Route 7", agency: "King County Metro"),
        PreviewRoute(id: "43", name: "Route 43", agency: "King County Metro")
    ]

    ListView(items: routes) { route in
        ListSubtitleRow(title: route.name, subtitle: route.agency)
    }
    .listViewStyle(.lazyVStack)
}

#Preview("Swipe actions") {
    let routes = [
        PreviewRoute(id: "5", name: "Route 5", agency: "King County Metro"),
        PreviewRoute(id: "7", name: "Route 7", agency: "King County Metro")
    ]

    ListView {
        ListSection(id: "routes", title: "Routes") {
            ForEach(routes) { route in
                ListSubtitleRow(title: route.name, subtitle: route.agency)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) { }
                        Button("Bookmark") { }.tint(.orange)
                    }
            }
        }
    }
}
