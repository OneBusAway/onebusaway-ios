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

/// A SwiftUI view representing a stop annotation on the map using pure SwiftUI rendering.
struct StopAnnotationContent: View {
    let stop: Stop
    let isBookmarked: Bool

    init(stop: Stop, isBookmarked: Bool = false) {
        self.stop = stop
        self.isBookmarked = isBookmarked
    }

    var body: some View {
        StopAnnotationIconView(stop: stop, isBookmarked: isBookmarked)
    }
}
