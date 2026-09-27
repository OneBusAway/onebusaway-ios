//
//  MessageView.swift
//  OBAKitWatch
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// One deliberate screen per empty or error state: an icon, a sentence, and
/// an optional action.
struct MessageView: View {
    let text: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
        } description: {
            Text(text)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
    }
}

#Preview("With action") {
    MessageView(text: "Something went wrong.", systemImage: "exclamationmark.triangle", actionTitle: "Retry") {}
}

#Preview("Without action") {
    MessageView(text: "No stops nearby.", systemImage: "bus")
}
