//
//  SearchFieldView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// A reusable search field component styled to match iOS standards
struct SearchFieldView: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let placeholder: String
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Search field with icon and clear button
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(placeholder, text: $text)
                    .focused($isFocused)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)

            // Cancel button (appears when focused)
            if isFocused {
                Button("Cancel") {
                    text = ""
                    isFocused = false
                    onCancel()
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}
