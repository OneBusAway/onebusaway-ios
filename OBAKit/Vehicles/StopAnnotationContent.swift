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

/// A SwiftUI view representing a stop annotation on the map
struct StopAnnotationContent: View {
    let stop: Stop

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 24, height: 24)
            Circle()
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(width: 24, height: 24)
            Image(systemName: iconName)
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
        }
        .shadow(color: .black.opacity(0.15), radius: 2)
    }

    private var iconName: String {
        switch stop.prioritizedRouteTypeForDisplay {
        case .lightRail, .subway, .rail:
            return "tram.fill"
        case .ferry:
            return "ferry.fill"
        case .bus:
            return "bus.fill"
        default:
            return "bus.fill"
        }
    }
}
