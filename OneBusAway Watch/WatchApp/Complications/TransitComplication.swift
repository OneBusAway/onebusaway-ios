//
//  TransitComplication.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//


import SwiftUI
import WidgetKit

struct TransitComplication: Widget {
    private let kind = "TransitComplication"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ComplicationProvider()) { entry in
            ComplicationView(arrival: entry.arrival)
        }
        .configurationDisplayName("OneBusAway")
        .description("Shows your next bus arrival time.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let arrival: Arrival?
    
    static var placeholder: ComplicationEntry {
        ComplicationEntry(date: Date(), arrival: Arrival.example)
    }
    
    static var empty: ComplicationEntry {
        ComplicationEntry(date: Date(), arrival: nil)
    }
}

