//
//  RefreshButton.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-18.
//

import SwiftUI
import AppIntents
import WidgetKit
import OBAKitCore

// MARK: - RefreshWidgetIntent
/// this intent serves as a way to refresh the widget and its timelines.
struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Widget"

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// A button to manually trigger the widget refresh.
struct RefreshButton: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    private var usesFullColor: Bool {
        widgetRenderingMode == .fullColor
    }

    private var foregroundColor: Color {
        usesFullColor ? .white : .primary
    }

    private var backgroundShape: some View {
        Group {
            if usesFullColor {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(uiColor: ThemeColors.shared.brand))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.primary.opacity(0.35), lineWidth: 1)
            }
        }
    }

    var body: some View {

        Button(intent: RefreshWidgetIntent()) {
            HStack(spacing: 2) {
                Image(systemName: "arrow.trianglehead.clockwise")
                    .imageScale(.small)

                Text("Refresh")
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .foregroundStyle(foregroundColor)
            .background(backgroundShape)
        }
        .buttonStyle(.plain)

    }
}
