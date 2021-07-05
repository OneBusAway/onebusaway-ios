//
//  ScheduleStatusViewModifier.swift
//  OBAKitCore
//
//  Created by Alan Chu on 5/20/21.
//

import SwiftUI

struct ScheduleStatusBackgroundViewModifier: ViewModifier {
    var scheduleStatus: ScheduleStatus

    func body(content: Content) -> some View {
        content
            .foregroundColor(Color(ThemeColors.shared.lightText))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // ↑ For resizable background frame. See preview "multiple labels of same size".
            .background(Color.scheduleStatus(scheduleStatus))
    }
}

struct ScheduleStatusForegroundViewModifier: ViewModifier {
    var scheduleStatus: ScheduleStatus

    func body(content: Content) -> some View {
        content
            .foregroundColor(Color.scheduleStatus(scheduleStatus))
    }
}

extension View {
    /// Applies the specified schedule status as the background color.
    ///
    /// - parameter scheduleStatus: The schedule status to apply to this view.
    ///
    /// ## Example Usage
    /// ```swift
    /// Text("5m")
    ///   .scheduleStatusBackground(.onTime)
    /// ```
    public func scheduleStatusBackground(_ scheduleStatus: ScheduleStatus) -> some View {
        self.modifier(ScheduleStatusBackgroundViewModifier(scheduleStatus: scheduleStatus))
    }

    /// Applies the specified schedule status as the foreground color.
    ///
    /// - parameter scheduleStatus: The schedule status to apply to this view.
    ///
    /// ## Example Usage
    /// The example below shows how to change the Text's font color to the schedule status corresponding to `.onTime`.
    /// ```swift
    /// Text("5m")
    ///   .scheduleStatusForeground(.onTime)
    /// ```
    public func scheduleStatusForeground(_ scheduleStatus: ScheduleStatus) -> some View {
        self.modifier(ScheduleStatusForegroundViewModifier(scheduleStatus: scheduleStatus))
    }
}

extension Color {
    /// The color indicator for the given `ScheduleStatus`.
    /// - parameter scheduleStatus: `ScheduleStatus`
    /// - returns: The corresponding color.
    ///
    /// ## Example Usage
    /// ```swift
    /// Text("5m")
    ///    .background(Color.scheduleStatus(.onTime))
    /// ```
    static public func scheduleStatus(_ scheduleStatus: ScheduleStatus) -> Color {
        switch scheduleStatus {
        case .delayed:
            return Color(ThemeColors.shared.departureLateBackground)
        case .early:
            return Color(ThemeColors.shared.departureEarlyBackground)
        case .onTime:
            return Color(ThemeColors.shared.departureOnTimeBackground)
        case .unknown:
            return Color(ThemeColors.shared.departureUnknownBackground)
        }
    }
}

struct ScheduleStatusViewModifierPreviews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .center, spacing: 16) {
            Text("3m")
                .scheduleStatusBackground(.onTime)
            Text("13m")
                .scheduleStatusBackground(.early)
            Text("12345m")
                .scheduleStatusBackground(.delayed)
            Image(systemName: "ant.fill")
                .scheduleStatusBackground(.early)
        }
        .fixedSize()
        .padding()
        .previewDisplayName("Multiple labels of same size")
        .previewLayout(.sizeThatFits)
    }
}
