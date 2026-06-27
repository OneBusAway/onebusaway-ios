//
//  ListItemActions.swift
//  OBAKit
//

import SwiftUI

/// A value type describing a single user-initiated action on a list item
/// (tap, swipe button, or context menu entry).

public struct ListAction: Identifiable {

    public var id: String { title }
    public let title: String
    public let image: Image?
    public let role: ButtonRole?
    public let tintColor: Color?
    public let handler: () -> Void

    // MARK: Init

    public init(
        title: String,
        image: Image? = nil,
        role: ButtonRole? = nil,
        tintColor: Color? = nil,
        handler: @escaping () -> Void
    ) {
        self.title = title
        self.image = image
        self.role = role
        self.tintColor = tintColor
        self.handler = handler
    }
}

// MARK: - OBAListElement

/// A protocol for view models that want automatic action wiring via `.listItemActions(for:)`.

public protocol ListElement: Identifiable {

    var onTapAction: (() -> Void)? { get }

    var leadingSwipeActions: [ListAction] { get }

    var trailingSwipeActions: [ListAction] { get }

    var contextMenuActions: [ListAction] { get }

}

public extension ListElement {

    var onTapAction: (() -> Void)? { nil }

    var leadingSwipeActions: [ListAction] { [] }

    var trailingSwipeActions: [ListAction] { [] }

    var contextMenuActions: [ListAction] { [] }

}

// MARK: - OBAItemActionModifier

public struct OBAItemActionModifier<Item: ListElement>: ViewModifier {

    public let item: Item

    // MARK: Body

    @ViewBuilder
    public func body(content: Content) -> some View {
        let hasActions = !item.leadingSwipeActions.isEmpty
            || !item.trailingSwipeActions.isEmpty
            || !item.contextMenuActions.isEmpty

        if hasActions {
            contentWithTap(content)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    ForEach(item.leadingSwipeActions) { actionButton(for: $0) }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    ForEach(item.trailingSwipeActions) { actionButton(for: $0) }
                }
                .contextMenu {
                    ForEach(item.contextMenuActions) { actionButton(for: $0) }
                }
        } else {
            contentWithTap(content)
        }
    }

    // MARK: Private Views

    @ViewBuilder
    private func contentWithTap(_ content: Content) -> some View {
        if let onTap = item.onTapAction {
            Button {
                onTap()
            } label: {
                content
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    @ViewBuilder
    private func actionButton(for action: ListAction) -> some View {
        Button(role: action.role, action: action.handler) {
            if let image = action.image {
                Label { Text(action.title) } icon: { image }
            } else {
                Text(action.title)
            }
        }
        .tint(action.tintColor)
    }
}

// MARK: - View Extension

extension View {
    /// Wires up tap, swipe, and context-menu actions.
    public func listItemActions<Item: ListElement>(for item: Item) -> some View {
        modifier(OBAItemActionModifier(item: item))
    }
}
