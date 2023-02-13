//
//  DepartureTimeBadgeView.swift
//  OBAKit
//
//  Created by Alan Chu on 2/9/23.
//

import SwiftUI
import OBAKitCore

struct DepartureTimeBadgeView: View {
    @Environment(\.themeColors) var themeColors

    // MARK: - Bindings
    var shouldFlashChanges: Bool

    @Binding var date: Date
    @Binding var temporalState: TemporalState
    @Binding var scheduleStatus: ScheduleStatus

    /// - parameter shouldFlashChanges: Briefly flash the `minutes` field if it changes value to visually notify the user of a new time.
    init(
        date: Binding<Date>,
        temporalState: Binding<TemporalState>,
        scheduleStatus: Binding<ScheduleStatus>,
        shouldFlashChanges: Bool = true
    ) {
        self._date = date
        self._temporalState = temporalState
        self._scheduleStatus = scheduleStatus
        self.shouldFlashChanges = shouldFlashChanges
    }

    // MARK: - Internal State

    /// We need to flash the background at the next available opportunity, such as when `isVisible == true`.
    @State private var pendingFlash: Bool = false

    /// Is the view currently visible? Value changes based on `.onAppear` and `.onDisappear`.
    @State private var isVisible: Bool = false

    /// Keep track of the last value
    private var lastShownMinutes: String?

    @State private var untilMinutes: Int = 0
    @State private var backgroundColor: Color = .clear

    var body: some View {
        Text(text)
            .foregroundColor(color)
            .background(backgroundColor)
            .font(.headline)
            .onChange(of: pendingFlash) { _ in
                flashBackgroundIfNeeded()
            }
            .onChange(of: date) { _ in
                updateUntilMinutes()
            }
            .onAppear {
                isVisible = true
                flashBackgroundIfNeeded()
                updateUntilMinutes()
            }
            .onDisappear {
                isVisible = false
            }
            .accessibilityAddTraits(.updatesFrequently)
    }

    private func updateUntilMinutes() {
        let oldUntilMinutes = untilMinutes
        untilMinutes = Int(date.timeIntervalSinceNow / 60.0)

        if oldUntilMinutes != untilMinutes {
            pendingFlash = true
        }
    }

    @MainActor
    private func flashBackgroundIfNeeded() {
        guard shouldFlashChanges else {
            return
        }

        if isVisible && pendingFlash {
            pendingFlash = false

            backgroundColor = Color(themeColors.propertyChanged)
            withAnimation(.easeOut.delay(0.5)) {
                backgroundColor = .clear
            }
        }
    }

    private var text: String {
        switch temporalState {
        case .present: return OBALoc("formatters.now", value: "NOW", comment: "Short formatted time text for arrivals/departures occurring now.")
        default:
            let formatString = OBALoc("formatters.short_time_fmt", value: "%dm", comment: "Short formatted time text for arrivals/departures. Example: 7m means that this event happens 7 minutes in the future. -7m means 7 minutes in the past.")
            return String(format: formatString, untilMinutes)
        }
    }

    private var color: Color {
        let _color: UIColor

        switch scheduleStatus {
        case .onTime:   _color = themeColors.departureOnTimeBackground
        case .early:    _color = themeColors.departureEarlyBackground
        case .delayed:  _color = themeColors.departureLateBackground
        default:        _color = themeColors.departureUnknownBackground
        }

        return Color(uiColor: _color)
    }
}

#if DEBUG
private struct PreviewView: View {
    @State var date: Date = .now
    @State var temporalState: TemporalState = .present
    @State var add30Seconds: TimeInterval = 1 {
        didSet {
            date = .now.addingTimeInterval(add30Seconds * 30)

            if add30Seconds < 0 {
                temporalState = .past
            } else if add30Seconds > 0 {
                temporalState = .future
            } else {
                temporalState = .present
            }
        }
    }

    var body: some View {
        VStack {
            DepartureTimeBadgeView(
                date: .constant(date),
                temporalState: .constant(temporalState),
                scheduleStatus: .constant(.delayed))

            Text(date, style: .relative)

            Stepper {
                Text("30 second increments")
            } onIncrement: {
                add30Seconds += 1
            } onDecrement: {
                add30Seconds -= 1
            }
        }
    }
}

struct DepartureTimeBadgeView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewView()
    }
}

#endif
