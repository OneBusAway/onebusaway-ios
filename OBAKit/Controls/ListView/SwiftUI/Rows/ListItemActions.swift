//
//  ListItemActions.swift
//  OBAKit
//

import SwiftUI

// MARK: - OBAItemActionModifier

/// Translates `OBAListElement` action properties into native SwiftUI modifiers.
///
/// Applied automatically via `.obaItemActions(for:)`. Handles:
/// - **Tap** — via `.onTapGesture` (avoids `Button` semantics interfering with row styling)
/// - **Leading / trailing swipe actions** — via `.swipeActions`
/// - **Context menu** — via `.contextMenu`
///
///     ForEach(items) { item in
///         ListSubtitleRow(title: item.name, subtitle: item.detail)
///             .obaItemActions(for: item)
///     }
///
public struct OBAItemActionModifier<Item: OBAListElement>: ViewModifier {

    // MARK: Stored Properties

    public let item: Item

    // MARK: Body

    public func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { item.onTapAction?() }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                ForEach(item.leadingSwipeActions) { action in
                    actionButton(for: action)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                ForEach(item.trailingSwipeActions) { action in
                    actionButton(for: action)
                }
            }
            .contextMenu {
                ForEach(item.contextMenuActions) { action in
                    actionButton(for: action)
                }
            }
    }

    // MARK: Private Views

    @ViewBuilder
    private func actionButton(for action: OBAListAction) -> some View {
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
    /// Wires up tap, swipe, and context-menu actions declared on an `OBAListElement`.
    public func obaItemActions<Item: OBAListElement>(for item: Item) -> some View {
        modifier(OBAItemActionModifier(item: item))
    }
}
