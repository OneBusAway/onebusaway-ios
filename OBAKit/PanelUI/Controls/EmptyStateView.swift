//
//  EmptyStateView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/28/25.
//

import SwiftUI

struct EmptyStateView: View {
    let iconName: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "mappin.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No Stops in This Area")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Zoom in to see nearby stops")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
