//
//  StopTravelPill.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI

/// A walk or bike time as a capsule, shared by both stop headers. Each supplies
/// its own chrome; the structure is fixed here because both got it wrong once.
///
/// - An `HStack`, not a `Label`. Both headers sit in a `List`, and a `Label` with
///   `.fixedSize` in a `List` row drew only its icon: the pill kept the title's
///   width, but the minutes never appeared (#1550).
/// - Not a `Button`. The pills sit in a `FlowLayout`, which sizes subviews with an
///   unspecified proposal, and a `Button` answers that with a greedy height. That
///   once stretched the sheet's walk pill down the whole sheet (5a95d4fe).
///   `directionsAction` makes it tappable instead.
struct StopTravelPill: View {
    let pill: StopDirectionsPill
    let info: WalkTimeInfo
    let font: Font
    let foreground: Color
    let fill: Color
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let directions: StopPillDirections

    var body: some View {
        let text = pill.text(for: info)
        HStack(spacing: 4) {
            Image(systemName: pill.systemImage)
            // One unwrappable line, so the pill's width is a function of its content.
            // Without it the pill came out 60pt wide and 168pt tall, with
            // "2 min walk" broken one character per line.
            Text(text)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(font)
        .foregroundStyle(foreground)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(fill, in: Capsule())
        .contentShape(Capsule())
        // Naming the element is what collapses the subtree. Hiding the glyph alone
        // still let it surface as a second VoiceOver stop whose whole content was the
        // symbol's stock name, "Walk".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .directionsAction(pill, directions)
    }
}
