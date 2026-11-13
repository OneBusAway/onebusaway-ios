//
//  DepartureTransferHighlight.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Shared visual treatment for a departure row that matches the rider's
/// inbound transfer trip (`TransferTripHighlight`).
enum DepartureTransferHighlight {
    /// - Parameter onSheetGlass: Whether the list sits on a sheet's Liquid
    ///   Glass (`drawsOnSheetGlass`). An ordinary row is then left clear so the
    ///   glass shows through; the transfer tint is translucent either way.
    static func rowBackground(isHighlighted: Bool, onSheetGlass: Bool = false) -> Color {
        if isHighlighted {
            Color(uiColor: ThemeColors.shared.brand).opacity(0.14)
        } else if onSheetGlass {
            .clear
        } else {
            Color(uiColor: .secondarySystemGroupedBackground)
        }
    }
}

extension View {
    /// A departure row's list background; see `DepartureTransferHighlight`.
    func departureRowBackground(isHighlighted: Bool) -> some View {
        modifier(DepartureRowBackground(isHighlighted: isHighlighted))
    }
}

private struct DepartureRowBackground: ViewModifier {
    let isHighlighted: Bool
    @Environment(\.drawsOnSheetGlass) private var onSheetGlass

    func body(content: Content) -> some View {
        content.listRowBackground(
            DepartureTransferHighlight.rowBackground(isHighlighted: isHighlighted, onSheetGlass: onSheetGlass)
        )
    }
}
