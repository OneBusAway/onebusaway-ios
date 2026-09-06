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
    static func rowBackground(isHighlighted: Bool) -> Color {
        if isHighlighted {
            Color(uiColor: ThemeColors.shared.brand).opacity(0.14)
        } else {
            Color(uiColor: .secondarySystemGroupedBackground)
        }
    }
}
