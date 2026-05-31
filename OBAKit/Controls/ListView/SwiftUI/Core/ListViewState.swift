//
//  ListViewState.swift
//  OBAKit
//

import SwiftUI

// MARK: - ListViewState

public enum ListViewState {
    case content
    case empty(EmptyStateConfiguration)
}

extension ListViewState: Equatable {
    public static func == (lhs: ListViewState, rhs: ListViewState) -> Bool {
        switch (lhs, rhs) {
        case (.content, .content):
            return true
        case (.empty(let l), .empty(let r)):
            return l == r
        default:
            return false
        }
    }
}

// MARK: - EmptyStateConfiguration

/// Configuration for the empty-state overlay shown when `ListViewState` is `.empty`.
///
/// - Note: Equality ignores `image` and `buttonAction` (non-equatable types).
///   Changing only the image or action closure will **not** trigger a view update.
public struct EmptyStateConfiguration {
    public let title: String
    public let body: String?
    public let image: Image?
    public let buttonTitle: String?
    public let buttonAction: (() -> Void)?

    public init(
        title: String,
        body: String? = nil,
        image: Image? = nil,
        buttonTitle: String? = nil,
        buttonAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.body = body
        self.image = image
        self.buttonTitle = buttonTitle
        self.buttonAction = buttonAction
    }

    /// A convenience factory that builds an empty state from an error.
    public static func error(_ error: Error) -> EmptyStateConfiguration {
        EmptyStateConfiguration(
            title: OBALoc(
                "list_empty_error_title",
                value: "Something Went Wrong",
                comment: "Title shown in the empty-state overlay when a list fails to load due to an error."
            ),
            body: error.localizedDescription,
            image: Image(systemName: "exclamationmark.triangle")
        )
    }
}

extension EmptyStateConfiguration: Equatable {
    // Equality intentionally ignores `image` and `buttonAction` (non-equatable).
    public static func == (lhs: EmptyStateConfiguration, rhs: EmptyStateConfiguration) -> Bool {
        lhs.title == rhs.title &&
        lhs.body == rhs.body &&
        lhs.buttonTitle == rhs.buttonTitle
    }
}

// MARK: - ListStateModifier

struct ListStateModifier: ViewModifier {
    let state: ListViewState

    func body(content: Content) -> some View {
        content.overlay { stateOverlay }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch state {
        case .content:
            EmptyView()
        case .empty(let config):
            ListEmptyStateView(configuration: config)
        }
    }
}

// MARK: - View Extension

extension View {
    public func listState(_ state: ListViewState) -> some View {
        modifier(ListStateModifier(state: state))
    }
}
