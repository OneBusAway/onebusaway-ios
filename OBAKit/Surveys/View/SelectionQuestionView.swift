//
//  SelectionQuestionView.swift
//  OBAKit
//
//  Created by Mohamed Sliem on 22/12/2025.
//

import SwiftUI
import OBAKitCore

struct SelectionQuestionView: View {

    let options: [String]

    let isMultipleSelection: Bool

    var onUpdateAnswer: (SurveyQuestionAnswer) -> Void

    // Internal state for saving the selected options
    @State private var selectionList: Set<String> = []

    var body: some View {
        VStack(spacing: 16) {
            ForEach(options.indices, id: \.self) { index in
                getOptionItemView(options[index])
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Components
    private func getOptionItemView(_ option: String) -> some View {
        HStack(spacing: 16) {
            optionIcon(option)
            optionText(option)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.clear)
                .stroke(colorFor(option: option))
        )
        .contentShape(.rect)
        .onTapGesture {
            onTapOptionItem(option)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option)
        .accessibilityValue(accessibilityValue(for: option))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isOptionSelected(option) ? .isSelected : [])
        .accessibilityHint(accessibilityHint)
    }

    private func optionIcon(_ option: String) -> some View {
        Image(systemName: iconName(for: option))
            .resizable()
            .frame(width: 18, height: 18)
            .fontWeight(.light)
            .foregroundStyle(colorFor(option: option))
            .padding(.top, 2)
    }

    private func optionText(_ option: String) -> some View {
        Text(option)
            .font(.body)
            .fontWeight(.regular)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func iconName(for option: String) -> String {
        let selected = selectionList.contains(option)

        if isMultipleSelection {
            return selected ? "checkmark.square.fill" : "square"
        } else {
            return selected ? "largecircle.fill.circle" : "circle"
        }
    }

    private func onTapOptionItem(_ option: String) {
        if !isMultipleSelection {
               selectionList = [option]
               onUpdateAnswer(.radio(option))
               return
           }

           if selectionList.contains(option) {
               selectionList.remove(option)
           } else {
               selectionList.insert(option)
           }

           onUpdateAnswer(.checkbox(selectionList))
    }

    //MARK: -  Helper Methods
    private func isOptionSelected(_ option: String) -> Bool {
        selectionList.contains(option)
    }

    private func colorFor(option: String) -> Color {
        isOptionSelected(option) ? ThemeColors.shared.brand.toColor() : ThemeColors.shared.gray.toColor()
    }


    // MARK: - Accessibility Helpers
    private func accessibilityValue(for option: String) -> String {
        isOptionSelected(option) ? "Selected" : "Not selected"
    }

    private var accessibilityHint: String {
        isMultipleSelection ? "Tap to toggle selection" : "Tap to select"
    }
}
