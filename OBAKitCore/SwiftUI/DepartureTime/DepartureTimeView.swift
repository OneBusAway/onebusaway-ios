//
//  DepartureTimeView.swift
//  OBAKitCore
//
//  Created by Alan Chu on 5/20/21.
//

import SwiftUI

/// A rounded time badge representing the provided upcoming departure time and deviation status.
/// A SwiftUI port of DepartureTimeBadge, except for the `highlightBackground` feature.
public struct DepartureTimeView: View {
    @Environment(\.obaFormatters) fileprivate var formatters

    // MARK: - View Model
    @State public var viewModel: DepartureTimeViewModel

    var minutes: Int {
        return Calendar.current.dateComponents([.minute], from: Date(), to: viewModel.arrivalDepartureDate).minute ?? 0
    }

    var displayText: String {
        return formatters.shortFormattedTime(
            untilMinutes: minutes,
            temporalState: viewModel.temporalState)
    }

    var accessibilityLabel: String {
        return formatters.formattedTimeUntilArrivalDeparture(
            arrivalDepartureMinutes: minutes,
            temporalState: viewModel.temporalState)
    }

    public init(viewModel: DepartureTimeViewModel) {
        self._viewModel = State(wrappedValue: viewModel)
    }

    // MARK: - View Attributes
    static let topBottomPadding = ThemeMetrics.compactPadding
    static let leftRightPadding = ThemeMetrics.buttonContentPadding

    public var body: some View {
        Text(displayText)
            .font(.headline)
            .padding([.top, .bottom], Self.topBottomPadding)
            .padding([.leading, .trailing], Self.leftRightPadding)
            .scheduleStatus(viewModel.scheduleStatus)
            .cornerRadius(8)
            .accessibility(label: Text(accessibilityLabel))
    }
}

struct DepartureTimeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            VStack(alignment: .center, spacing: 16) {
                DepartureTimeView(viewModel: .DEBUG_departingNOWOnTime)
                DepartureTimeView(viewModel: .DEBUG_departingIn12MinutesOnTime)
                DepartureTimeView(viewModel: .DEBUG_departingIn20MinutesScheduled)
                DepartureTimeView(viewModel: .DEBUG_departed11MinutesAgoEarly)
                DepartureTimeView(viewModel: .DEBUG_arrivingIn3MinutesLate)
                DepartureTimeView(viewModel: .DEBUG_arrivingIn124MinutesScheduled)
            }
            .fixedSize()
            .previewDisplayName("Standard Content Size")

            VStack(alignment: .center, spacing: 16) {
                DepartureTimeView(viewModel: .DEBUG_departingNOWOnTime)
                DepartureTimeView(viewModel: .DEBUG_departingIn12MinutesOnTime)
                DepartureTimeView(viewModel: .DEBUG_departingIn20MinutesScheduled)
                DepartureTimeView(viewModel: .DEBUG_departed11MinutesAgoEarly)
                DepartureTimeView(viewModel: .DEBUG_arrivingIn3MinutesLate)
                DepartureTimeView(viewModel: .DEBUG_arrivingIn124MinutesScheduled)
            }
            .fixedSize()
            .environment(\.sizeCategory, .accessibilityLarge)
            .previewDisplayName("Accessibility Content Size")
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
