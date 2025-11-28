//
//  FloatingPanelContentView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/27/25.
//

import SwiftUI
import FloatingPanel

struct FloatingPanelContentView<Content: View>: View {
    var proxy: FloatingPanelProxy
    let content: Content

    init(proxy: FloatingPanelProxy, @ViewBuilder content: () -> Content) {
        self.proxy = proxy
        self.content = content()
    }

    var body: some View {
        content
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .floatingPanelScrollTracking(proxy: proxy)
    }
}
