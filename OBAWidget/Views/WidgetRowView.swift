//
//  WidgetMediumView.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-16.
//

import SwiftUI
import WidgetKit
import OBAKitCore

// MARK: - Constants
private enum Constants {
    static let minutes: UInt = 60
    static let maxDeparturesToShow = 3
    static let rowWidth: CGFloat = 180
    static let fontSize: CGFloat = 13
}

// MARK: - WidgetRowView
struct WidgetRowView: View {
    let bookmark: Bookmark?
    let formatters: Formatters
    let departures: [ArrivalDeparture]?
    
    private var bookmarkTitle: String {
        bookmark?.name ?? " "
    }
    
    private var nextDepartureLabel: String {
        if departures != nil {
            return updateNextDepartureLabel()
        } else {
            return OBALoc("today_screen.tap_for_more_information",
                          value: "Tap for more information",
                          comment: "Tap for more information subheading on Today view")
        }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(bookmarkTitle)
                    .font(.system(size: Constants.fontSize,
                                  weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Text(nextDepartureLabel)
                    .font(.system(size: Constants.fontSize))
                    .foregroundStyle(.secondary)
            }
            .frame(width: Constants.rowWidth,
                   alignment: .leading )
            
            Spacer()
            
            departureTimeBadges
        }
    }
    
    // MARK: - Departure Time Badges
    private var departureTimeBadges: some View {
        HStack(spacing: 5) {
            ForEach(departures?.prefix(Constants.maxDeparturesToShow) ?? [], id: \.self) { departure in
                DepartureTimeBadgeView(
                    arrivalDeparture: departure,
                    formatters: formatters
                )
            }
        }
    }
    
    // MARK: - Helper Functions
    private func updateNextDepartureLabel() -> String {
        guard let departures = departures else {
            return OBALoc("today_screen.tap_for_more_information",
                          value: "Tap for more information",
                          comment: "Tap for more information subheading on Today view")
        }
        
        if let firstDeparture = departures.first {
            return formatters.formattedScheduleDeviation(for: firstDeparture)
        } else {
            return String(format: OBALoc("today_view.no_departures_in_next_n_minutes_fmt",
                                         value: "No departures in the next %@ minutes",
                                         comment: ""),
                          String(Constants.minutes))
        }
    }
}

// MARK: - Preview
struct Widget_Previews: PreviewProvider {
    static var previews: some View {
        WidgetRowView(bookmark: nil,
                      formatters: WidgetDataProvider.shared.formatters,
                      departures: [])
        .containerBackground(.ultraThinMaterial.quaternary, for: .widget)
        .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
}
