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
                .frame(maxWidth: .infinity)
                .background(.background)
        } else {
            VStack(alignment: .center, content: contents)
                .multilineTextAlignment(.center)
                .font(.largeTitle)
                .frame(maxWidth: .infinity)
                .background(.background)
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

        ZStack {
            Color.red
            OnboardingHeaderView(imageSystemName: "globe", headerText: "Hello, World!")
        }
        .previewDisplayName("Testing Background of OnboardingHeaderView")
    }
}
