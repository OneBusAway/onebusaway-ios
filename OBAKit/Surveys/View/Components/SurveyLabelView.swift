//
//  SurveyLabelView.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 23/12/2025.
//

import SwiftUI
import OBAKitCore

struct SurveyLabelView: View {

    let textContent: String

    var body: some View {
        Text(textContent)
            .font(.body)
            .multilineTextAlignment(.leading)
            .lineSpacing(4)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 70)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(UIColor.tertiarySystemBackground.toColor())
                    .shadow(color: .gray.opacity(0.4), radius: 3)
            }
            .accessibilityLabel(Strings.surveyLabel)
            .accessibilityValue(textContent)
            .accessibilityAddTraits(.isStaticText)
            .padding(.horizontal, 12)
    }

}

#Preview {
    SurveyLabelView(textContent: "Are the")
}
