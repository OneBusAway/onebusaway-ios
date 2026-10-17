//
//  StatusGlyphLabel.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// A countdown chip's text, with its status glyph beside it when Differentiate
/// Without Color is on. Otherwise the chip's tint is the only sign of whether
/// the vehicle is early, late, on time or only scheduled.
struct StatusGlyphLabel: View {
    let text: String
    let status: DepartureStatus

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        HStack(spacing: 3) {
            if differentiateWithoutColor {
                Image(systemName: status.glyphName).imageScale(.small)
            }
            Text(text)
        }
    }
}
