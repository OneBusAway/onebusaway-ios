//
//  ExternalSurveyView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

struct ExternalSurveyView: View {

    let question: SurveyQuestion

    let onCloseAction: () -> Void

    let onSubmitAction: () -> Void

    init(question: SurveyQuestion, onCloseAction: @escaping () -> Void, onSubmitAction: @escaping () -> Void) {
        self.question = question
        self.onCloseAction = onCloseAction
        self.onSubmitAction = onSubmitAction
    }

    var body: some View {
        VStack(spacing: 8) {
            titleView
            subtitleView
            optionsStack
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(UIColor.tertiarySystemBackground.toColor())
        )
    }

    private var titleView: some View {
        Text(question.content.labelText)
            .font(.headline)
            .fontWeight(.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitleView: some View {
        Text(Strings.externalSurveyPrivacyInfo)
            .font(.footnote)
            .foregroundStyle(UIColor.darkGray.toColor())
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var optionsStack: some View {
        HStack(spacing: 16) {
            cancelSurveyButton
            goButton
        }
        .padding(.top, 8)
    }

    private var goButton: some View {
        actionButton(
            title: Strings.go,
            systemImage: "arrow.up.right",
            font: .body,
            horizontalPadding: 22,
            verticalPadding: 6,
            action: onSubmitAction
        )
    }

    private var cancelSurveyButton: some View {
        actionButton(
            title: Strings.doNotShowAgain,
            systemImage: "xmark",
            font: .footnote,
            action: onCloseAction
        )
    }

    private func actionButton(
        title: String,
        systemImage: String,
        font: Font,
        horizontalPadding: CGFloat = 16,
        verticalPadding: CGFloat = 8,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .resizable()
                    .frame(width: 13, height: 13)
                    .fontWeight(.bold)

                Text(title)
                    .font(font)
                    .fontWeight(.bold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(ThemeColors.shared.brand.toColor())
            )
        }
        .buttonStyle(.plain)
    }

}

#Preview {
    ExternalSurveyView(
        question: .init(
            id: 1,
            position: 1,
            required: true,
            content: .init(labelText: "External Survey Question", type: .externalSurvey)
        ),
        onCloseAction: {

        }, onSubmitAction: {

        }
    )
    .padding(.horizontal, 16)

}
