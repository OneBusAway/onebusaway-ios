//
//  ExternalSurveyView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//
/

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
        HStack(spacing: 24) {
            VStack(spacing: 12) {
                titleView
                subtitleView
            }

            goButton
                .padding(.trailing, 18)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .overlay(alignment: .topTrailing) {
            closeButton
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(UIColor.tertiarySystemBackground.toColor())
        )
    }

    private var titleView: some View {
        Text(question.content.labelText)
            .font(.headline)
            .fontWeight(.medium)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitleView: some View {
        Text(Strings.externalSurveyPrivacyInfo)
            .font(.footnote)
            .foregroundStyle(UIColor.darkGray.toColor())
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var goButton: some View {
        Button {
            onSubmitAction()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.right")
                    .resizable()
                    .frame(width: 13, height: 13)
                    .fontWeight(.medium)

                Text(Strings.go)
                    .font(.body)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.white)
            .padding(6)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(ThemeColors.shared.brand.toColor())
            )
        }
        .buttonStyle(.plain)
    }

    private var closeButton: some View {
        Button {
            onCloseAction()
        } label: {
            Image(systemName: "xmark")
                .resizable()
                .fontWeight(.bold)
                .frame(width: 14, height: 14)
                .foregroundStyle(UIColor.label.toColor())
        }
        .buttonStyle(.plain)
        .padding(12)
        .padding(.top, 2)
    }
}

#Preview {
    ExternalSurveyView(
        question: .init(
            id: 1,
            position: 1,
            required: true,
            content: .init(labelText: "External Survey Question External Survey Question External Survey Question", type: .externalSurvey)
        ),
        onCloseAction: {

        }, onSubmitAction: {

        }
    )

}
