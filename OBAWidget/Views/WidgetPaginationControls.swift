//
//  WidgetPaginationControls.swift
//  OBAWidget
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import AppIntents
import OBAKitCore
import SwiftUI
import WidgetKit

/// Compact previous/next pagination controls and page indicator for `.systemMedium` widgets.
struct WidgetPaginationControls: View {
    let currentPage: Int
    let totalPages: Int

    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    private var usesFullColor: Bool {
        widgetRenderingMode == .fullColor
    }

    var body: some View {
        HStack(spacing: 2) {
            Button(intent: PreviousBookmarkPageIntent()) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                    // Wider than the glyph so it's easier to hit. 24 tall
                    // matches the refresh button next to it.
                    .frame(minWidth: 28, minHeight: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: WidgetStrings.previousPage))

            Text(verbatim: "\(currentPage + 1)/\(totalPages)")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityLabel(Text(verbatim: WidgetStrings.pageIndicator(current: currentPage + 1, total: totalPages)))

            Button(intent: NextBookmarkPageIntent()) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .frame(minWidth: 28, minHeight: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: WidgetStrings.nextPage))
        }
        .padding(.horizontal, 2)
        .background(backgroundShape)
        .invalidatableContent()
    }

    @ViewBuilder
    private var backgroundShape: some View {
        if usesFullColor {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.primary.opacity(0.35), lineWidth: 1)
        }
    }
}
