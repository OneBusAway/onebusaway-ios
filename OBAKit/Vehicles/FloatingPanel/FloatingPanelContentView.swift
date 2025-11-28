//
//  FloatingPanelContentView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/27/25.
//

import SwiftUI
import FloatingPanel


//struct MapContainerView<Content: View>: View {
//    let content: Content
//
//    init(@ViewBuilder content: () -> Content) {
//        self.content = content()
//    }
//
//    var body: some View {
//        content
//            .padding(8)
//            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
//    }
//}


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

//    var body: some View {
//        VStack(spacing: 0) {
//            searchBar
//            ResultsList()
//                .ignoresSafeArea() // Needs here with `floatingPanelScrollTracking(proxy:)` on iOS 15
//
//        }
//        // 👇🏻 for the floating panel grabber handle.
//        .padding(.top, 6)
//        .background(
//            VisualEffectBlur(blurStyle: .systemMaterial)
//                // ⚠️ If the `VisualEffectBlur` view receives taps, it's going
//                // to mess up with the whole panel and render it
//                // non-interactive, make sure it never receives any taps.
//                .allowsHitTesting(false)
//        )
//        .ignoresSafeArea()
//    }
}
