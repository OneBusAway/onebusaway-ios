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

/// A stop icon matching the map annotation style (rounded square with directional triangle)
struct StopIconView: View {
    let stop: Stop
    let iconFactory: StopIconFactory

    var body: some View {
        Image(uiImage: iconFactory.buildIcon(for: stop, isBookmarked: false, traits: UITraitCollection.current))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 32, height: 32)
    }
}
