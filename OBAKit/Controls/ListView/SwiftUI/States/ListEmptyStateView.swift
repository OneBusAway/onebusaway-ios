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
        ListStateOverlay {
            VStack(spacing: 16) {
                Spacer()
                imageView
                textContent
                actionButton
                Spacer()
            }
            .padding(.horizontal, 32)
        }
    }

    // MARK: Private Views

    @ViewBuilder
    private var imageView: some View {
        if let image = configuration.image {
            image
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
        }
    }

    private var textContent: some View {
        VStack(spacing: 8) {
            Text(configuration.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            if let body = configuration.body {
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if let buttonTitle = configuration.buttonTitle,
           let action = configuration.buttonAction {
            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
        }
    }
}

// MARK: - Previews

#Preview("With image and button") {
    ListEmptyStateView(configuration: EmptyStateConfiguration(
        title: "No Stops Nearby",
        body: "Move the map or search for a stop to see upcoming arrivals.",
        image: Image(systemName: "mappin.slash"),
        buttonTitle: "Search",
        buttonAction: {}
    ))
}

#Preview("Error state") {
    ListEmptyStateView(
        configuration: .error(URLError(.notConnectedToInternet))
    )
}

#Preview("Title only") {
    ListEmptyStateView(configuration: .standard(title: "No Results"))
}
