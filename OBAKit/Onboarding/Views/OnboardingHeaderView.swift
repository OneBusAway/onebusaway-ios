//
//  OnboardingHeaderView.swift
//  OBAKit
//
//  Created by Alan Chu on 1/6/23.
//

import SwiftUI
import OBAKitCore

struct OnboardingHeaderView: View {
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    @State var imageSystemName: String
    @State var headerText: String

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            HStack(alignment: .center, content: contents)
        } else {
            VStack(alignment: .center, content: contents)
                .font(.largeTitle)
        }
    }

    @ViewBuilder
    private func contents() -> some View {
        Image(systemName: imageSystemName)
            .foregroundColor(.white)
            .padding(16)
            .background(Color(uiColor: ThemeColors.shared.brand))
            .clipShape(Circle())

        Text(headerText)
            .bold()
    }
}

struct OnboardingHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingHeaderView(imageSystemName: "globe", headerText: "Hello, World!")
    }
}
