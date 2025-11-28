//
//  StopAnnotationContent.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// A SwiftUI view representing a stop annotation on the map, using the same icon rendering as the UIKit map
struct StopAnnotationContent: View {
    let stop: Stop
    let iconFactory: StopIconFactory

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(uiImage: stopIcon)
    }

    private var stopIcon: UIImage {
        // Create a UITraitCollection to pass to the icon factory for dark mode support
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        return iconFactory.buildIcon(for: stop, isBookmarked: false, traits: traits)
    }
}
