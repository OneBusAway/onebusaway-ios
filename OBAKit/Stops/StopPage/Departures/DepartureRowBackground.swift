//
//  DepartureRowBackground.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

extension View {
    /// A departure row's list background. A row matching the rider's inbound
    /// transfer trip (`TransferTripHighlight`) is tinted; any other row is
    /// opaque, or left clear on sheet glass (`drawsOnSheetGlass`) so the glass
    /// shows through.
    func departureRowBackground(isHighlighted: Bool) -> some View {
        modifier(DepartureRowBackground(isHighlighted: isHighlighted))
    }
}

private struct DepartureRowBackground: ViewModifier {
    let isHighlighted: Bool
    @Environment(\.drawsOnSheetGlass) private var onSheetGlass

    func body(content: Content) -> some View {
        content.listRowBackground(background)
    }

    private var background: Color {
        if isHighlighted {
            Color(uiColor: ThemeColors.shared.brand).opacity(0.14)
        } else if onSheetGlass {
            .clear
        } else {
            Color(uiColor: .secondarySystemGroupedBackground)
        }
    }
}

extension EnvironmentValues {
    /// Whether these views sit directly on a sheet's Liquid Glass (iOS 26+), so
    /// surfaces that would otherwise paint an opaque background stay clear.
    ///
    /// Set by the map panel's stop sheet. The pushed Stop page shares its
    /// departure rows and leaves this off, keeping them opaque.
    @Entry var drawsOnSheetGlass = false
}
