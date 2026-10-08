//
//  CopyableValueRow.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import UIKit
import OBAKitCore

/// A read-only `title: value` row that copies `value` to the clipboard when
/// tapped, briefly showing "Copied to clipboard" in place of the value.
///
/// VoiceOver reads it as one button ("Stop ID, 1_75403, button") with
/// `accessibilityHint`, and announces the confirmation, since it replaces the
/// value without moving focus.
struct CopyableValueRow: View {
    let title: String
    let value: String
    var accessibilityHint: String?

    @State private var showsConfirmation = false
    @State private var revertTask: Task<Void, Never>?

    private var confirmation: String {
        OBALoc("clipboard.copied_text_confirmation", value: "Copied to clipboard", comment: "This is displayed to confirm that something has been copied to clipboard.")
    }

    var body: some View {
        Button(action: copy) {
            LabeledContent(title, value: showsConfirmation ? confirmation : value)
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityHint(accessibilityHint ?? "")
        .onDisappear {
            // Form rows disappear when scrolled away; reset too, or the
            // cancelled revert leaves "Copied to clipboard" showing for good.
            revertTask?.cancel()
            showsConfirmation = false
        }
    }

    private func copy() {
        UIPasteboard.general.string = value
        AccessibilityAnnouncement.post(confirmation)
        showsConfirmation = true
        revertTask?.cancel()
        revertTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            showsConfirmation = false
        }
    }
}
