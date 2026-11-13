//
//  SheetGlass.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

extension EnvironmentValues {
    /// Whether these views sit directly on a sheet's Liquid Glass (iOS 26+), so
    /// surfaces that would otherwise paint an opaque background stay clear.
    ///
    /// Set by the map panel's stop sheet. The pushed Stop page shares its
    /// header and departure rows and leaves this off, keeping them opaque. At
    /// the full-height detent the system turns the sheet's glass opaque by
    /// itself, so the cleared surfaces read as a plain white page there.
    @Entry var drawsOnSheetGlass = false
}

extension View {
    /// `systemBackground`, or nothing when the view sits on sheet glass; see
    /// `drawsOnSheetGlass`.
    func opaqueUnlessOnSheetGlass() -> some View {
        modifier(OpaqueUnlessOnSheetGlass())
    }
}

private struct OpaqueUnlessOnSheetGlass: ViewModifier {
    @Environment(\.drawsOnSheetGlass) private var onSheetGlass

    func body(content: Content) -> some View {
        content.background(onSheetGlass ? Color.clear : Color(uiColor: .systemBackground))
    }
}
