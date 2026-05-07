//
//  ListViewState.swift
//  OBAKit
//

import SwiftUI

// MARK: - ListViewState

/// Represents the display state of a `ListView`.
public enum ListViewState {
    case content
    case loading
    case empty(EmptyStateConfiguration)
}

extension ListViewState: Equatable {
    public static func == (lhs: ListViewState, rhs: ListViewState) -> Bool {
        switch (lhs, rhs) {
        case (.content, .content): return true
        case (.loading, .loading): return true
        case (.empty(let l), .empty(let r)): return l == r
        default: return false
        }
    }
}

// MARK: - EmptyStateConfiguration

/// Configuration for the empty-state overlay shown when `ListViewState` is `.empty`.
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

    /// A convenience factory for standard informational empty states.
    public static func standard(
        title: String,
        body: String? = nil,
        image: Image? = nil
    ) -> EmptyStateConfiguration {
        EmptyStateConfiguration(title: title, body: body, image: image)
    }

    /// A convenience factory that builds an empty state from an error.
    public static func error(_ error: Error) -> EmptyStateConfiguration {
        EmptyStateConfiguration(
            title: NSLocalizedString("list_empty_error_title", value: "Something Went Wrong", comment: ""),
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
        ZStack {
            content
            stateOverlay
        }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch state {
        case .content:
            EmptyView()
        case .loading:
            ListLoadingView()
        case .empty(let config):
            ListEmptyStateView(configuration: config)
        }
    }
}

// MARK: - View Extension

extension View {
    /// Overlays a loading or empty-state view on top of the receiver.
    ///
    ///     ListView(items: stops) { ListRow(title: $0.name) }
    ///         .listState(viewModel.state)
    public func listState(_ state: ListViewState) -> some View {
        modifier(ListStateModifier(state: state))
    }
}
