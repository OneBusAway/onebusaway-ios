//
//  ToastView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

struct ToastView: View {

    let toast: Toast

    var body: some View {
        HStack(spacing: 12) {
            messageIcon
            messageText
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(containerBackground)
        .padding(.horizontal, 20)
        // One element: the icon is decoration, and the message is the toast.
        .accessibilityElement(children: .combine)
    }

    // Text styles rather than fixed point sizes, so the toast follows Dynamic
    // Type: `.title3` and `.subheadline` are the 20pt and ~14pt of the default size.
    private var messageIcon: some View {
        Image(systemName: toast.type.icon)
            .foregroundColor(.white)
            .font(.title3)
            .accessibilityHidden(true)
    }

    private var messageText: some View {
        Text(toast.message)
            .font(.subheadline.weight(.medium))
            .foregroundColor(.white)
            .lineSpacing(3)
    }

    private var containerBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(toast.type.color)
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
    }

}

// MARK: - Modifier

struct ToastModifier: ViewModifier {

    @EnvironmentObject var manager: ToastManager

    let message: String?
    let type: Toast.ToastType?
    let duration: TimeInterval

    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        ZStack {
            content

            if let toast = manager.toast {
                VStack {
                    ToastView(toast: toast)
                        .offset(y: manager.isShowing ? 0 : -150)
                        .opacity(manager.isShowing ? 1 : 0)

                    Spacer()
                }
            }
        }
        .onChange(of: isPresented) { _, newValue in
            if newValue == true, let message = message, let type = type {

                switch type {
                case .success:
                    manager.showSuccess(message, duration: duration)
                case .error:
                    manager.showError(message, duration: duration)
                }

                isPresented = false
            }
        }
    }
}

extension View {
    func toast(toast: Toast?, isPresented: Binding<Bool>, duration: TimeInterval = 3.0) -> some View {
        self.modifier(ToastModifier(
            message: toast?.message,
            type: toast?.type,
            duration: duration,
            isPresented: isPresented
        ))
    }
}
