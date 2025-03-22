//
//  ComplicationView.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//


import SwiftUI
import WidgetKit

struct ComplicationView: View {
    let arrival: Arrival?
    
    // Dynamic sizing for different complication families
    @Environment(\.widgetFamily) var widgetFamily
    
    var body: some View {
        Group {
            switch widgetFamily {
            case .accessoryCircular:
                circularView
            case .accessoryRectangular:
                rectangularView
            case .accessoryInline:
                inlineView
            default:
                defaultView
            }
        }
        .widgetAccentable()
    }
    
    // Circular complication view
    private var circularView: some View {
        ZStack {
            if let arrival = arrival {
                VStack(spacing: 0) {
                    Text(arrival.routeShortName)
                        .font(.system(size: 12, weight: .bold))
                        .minimumScaleFactor(0.8)
                    
                    Text(arrival.minutesUntilArrival)
                        .font(.system(size: 10))
                        .foregroundColor(arrival.isLate ? .red : .green)
                }
            } else {
                VStack(spacing: 0) {
                    Text("OBA")
                        .font(.system(size: 10, weight: .bold))
                    Text("--")
                        .font(.system(size: 10))
                }
            }
        }
    }
    
    // Rectangular complication view
    private var rectangularView: some View {
        HStack {
            if let arrival = arrival {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(arrival.routeShortName)
                            .font(.system(size: 14, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(arrival.routeColor)
                            .foregroundColor(.white)
                            .cornerRadius(3)
                        
                        Text(arrival.headsign)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    
                    HStack {
                        Text(arrival.formattedArrivalTime)
                            .font(.system(size: 12))
                        
                        Text(arrival.minutesUntilArrival)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(arrival.isLate ? .red : .green)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("OneBusAway")
                        .font(.system(size: 14, weight: .bold))
                    
                    Text("No upcoming arrivals")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.leading, 4)
    }
    
    // Inline complication view
    private var inlineView: some View {
        if let arrival = arrival {
            Text("\(arrival.routeShortName): \(arrival.minutesUntilArrival)")
        } else {
            Text("No arrivals")
        }
    }
    
    // Default complication view
    private var defaultView: some View {
        VStack(spacing: 2) {
            if let arrival = arrival {
                Text(arrival.routeShortName)
                    .font(.headline)
                
                Text(arrival.minutesUntilArrival)
                    .font(.subheadline)
                    .foregroundColor(arrival.isLate ? .red : .green)
            } else {
                Text("No arrivals")
                    .font(.caption)
            }
        }
    }
}

struct ComplicationView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ComplicationView(arrival: Arrival.example)
                .previewContext(WidgetPreviewContext(family: .accessoryCircular))
                .previewDisplayName("Circular")
            
            ComplicationView(arrival: Arrival.example)
                .previewContext(WidgetPreviewContext(family: .accessoryRectangular))
                .previewDisplayName("Rectangular")
            
            ComplicationView(arrival: Arrival.example)
                .previewContext(WidgetPreviewContext(family: .accessoryInline))
                .previewDisplayName("Inline")
            
            ComplicationView(arrival: nil)
                .previewContext(WidgetPreviewContext(family: .accessoryCircular))
                .previewDisplayName("No Arrivals")
        }
    }
}

