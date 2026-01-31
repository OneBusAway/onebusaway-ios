//
//  TextQuestionView.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 23/12/2025.
//

import SwiftUI
import OBAKitCore

struct TextQuestionView: View {

    let onUpdateAnswer: (SurveyQuestionAnswer) -> Void

    @State private var text: String = ""

    init(text: String = "", onUpdateAnswer: @escaping (SurveyQuestionAnswer) -> Void) {
        self._text = State(wrappedValue: text)
        self.onUpdateAnswer = onUpdateAnswer
    }

    var body: some View {
        TextEditor(text: $text)
            .foregroundStyle(.primary)
            .scrollContentBackground(.hidden)
            .clipShape(.rect(cornerRadius: 8))
            .font(.body)
            .frame(height: 100)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(textEditorBorder)
            .padding([.horizontal, .bottom], 8)
            .accessibilityLabel("Answer input")
            .accessibilityHint("Enter your answer to the survey question")
            .accessibilityValue(text)
            .onChange(of: text) { _, newValue in
                onUpdateAnswer(.text(newValue))
            }

    }

    private var textEditorBorder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(UIColor.tertiarySystemBackground.toColor())
            .stroke(.gray, lineWidth: 0.5)
    }

}

#Preview {
    TextQuestionView(onUpdateAnswer: { _ in

    })
}
