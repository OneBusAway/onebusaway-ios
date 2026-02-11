//
//  StopIconView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// A stop icon view for use in list rows, matching the map annotation style.
/// Renders a rounded square with transport icon, gradient background, and directional triangle.
struct StopIconView: View {
    let stop: Stop
    let size: CGFloat
    let isBookmarked: Bool

    /// Default icon size for list rows (smaller than map annotations)
    private static let defaultSize: CGFloat = 32

    /// Base size of StopAnnotationIconView (must match the constant in that view)
    private static let baseIconSize: CGFloat = 48

    init(stop: Stop, size: CGFloat = defaultSize, isBookmarked: Bool = false) {
        self.stop = stop
        self.size = size
        self.isBookmarked = isBookmarked
    }

    var body: some View {
        StopAnnotationIconView(stop: stop, isBookmarked: isBookmarked)
            .scaleEffect(size / Self.baseIconSize)
            .frame(width: size, height: size)
    }
}
