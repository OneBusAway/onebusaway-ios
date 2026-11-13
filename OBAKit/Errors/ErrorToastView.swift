//
//  ErrorToastView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// What an ``ErrorToastView`` shows. Independent of `ErrorReport` so any
/// surface can raise a toast of its own.
struct ErrorToast: Equatable {
    enum Style {
        /// Orange "!": the problem is on our side or the agency's.
        case problem
        /// Grey "i": the fix is on the rider's side (settings, network).
        case riderAction
    }

    let title: String
    /// A second line under the title; a notice has none.
    let message: String?
    let style: Style
    /// The button's title; a notice has no button.
    let actionTitle: String?
}

extension ErrorToast {
    init(report: ErrorReport) {
        self.title = report.title
        self.message = report.summary
        self.style = report.cause.isRiderActionable ? .riderAction : .problem
        switch report.action {
        case .details: self.actionTitle = ErrorStrings.details
        case .openSettings: self.actionTitle = Strings.settings
        }
    }

    /// A one-line notice with nothing behind it, such as Settings' "couldn't
    /// turn on speed sync". The fix is the rider's, so it gets the grey "i".
    init(notice: String) {
        self.title = notice
        self.message = nil
        self.style = .riderAction
        self.actionTitle = nil
    }
}

/// A short, non-modal error notice with one action, shown over the bottom of
/// the screen. Replaces the modal error bulletin (#1582): the rest of the
/// screen stays usable while it's up.
struct ErrorToastView: View {
    let toast: ErrorToast
    var onAction: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if let message = toast.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if let actionTitle = toast.actionTitle {
                Button(actionTitle, action: onAction)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(uiColor: ThemeColors.shared.brand))
                    .buttonStyle(.plain)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.11))
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 8)
        )
        // Always dark, so the brand color resolves to its dark-mode variant,
        // which reads on the dark card.
        .environment(\.colorScheme, .dark)
        .gesture(
            DragGesture(minimumDistance: 10).onEnded { value in
                if value.translation.height > 20 { onDismiss() }
            }
        )
        .accessibilityAction(.escape, onDismiss)
    }

    private var icon: some View {
        Text(toast.style == .problem ? "!" : "i")
            .font(.system(.footnote, design: .rounded).weight(.heavy))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(toast.style == .problem ? Color.orange : Color.gray))
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Problem") {
    VStack {
        Spacer()
        ErrorToastView(
            toast: ErrorToast(title: "Couldn't load live position", message: "The server is busy.", style: .problem, actionTitle: "Details"),
            onAction: {}, onDismiss: {}
        )
        ErrorToastView(
            toast: ErrorToast(title: "Cellular data is off", message: "Turn it on in Settings, or use Wi-Fi.", style: .riderAction, actionTitle: "Settings"),
            onAction: {}, onDismiss: {}
        )
    }
    .padding(12)
}
#endif
