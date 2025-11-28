//
//  MapOverlayView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/26/25.
//

import SwiftUI

struct MapOverlayView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
