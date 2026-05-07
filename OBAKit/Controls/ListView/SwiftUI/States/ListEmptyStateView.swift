//
//  ListEmptyStateView.swift
//  OBAKit
//

import SwiftUI

/// Full-screen empty-state overlay used by `ListStateModifier` when state is `.empty`.
struct ListEmptyStateView: View {

    // MARK: Stored Properties

    let configuration: EmptyStateConfiguration

    // MARK: Body

    var body: some View {
        ContentUnavailableView {
            if let image = configuration.image {
                Label {
                    Text(configuration.title)
                } icon: {
                    image
                }
            } else {
                Text(configuration.title)
            }
        } description: {
            if let body = configuration.body {
                Text(body)
            }
        } actions: {
            if let buttonTitle = configuration.buttonTitle,
               let action = configuration.buttonAction {
                Button(buttonTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
    }
}
