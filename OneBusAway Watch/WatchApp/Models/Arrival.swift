//
//  Arrival.swift
//  OBAKit
//
//  Created by Prince Yadav on 06/03/25.
//


import Foundation
import SwiftUI

struct Arrival: Identifiable, Codable {
    let id: String
    let routeId: String
    let routeShortName: String
    let headsign: String
    let scheduledArrivalTime: Date
    let predictedArrivalTime: Date?
    let routeColorHex: String
    let tripId: String?
    let status: String?
    
    // Formatted arrival time (e.g., "10:30 AM")
    var formattedArrivalTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        
        // Check if we should show seconds
        if UserDefaults.standard.bool(forKey: "showSeconds") {
            formatter.timeStyle = .medium
        }
        
        return formatter.string(from: predictedArrivalTime ?? scheduledArrivalTime)
    }
    
    // Minutes until arrival (e.g., "5 min" or "Due")
    var minutesUntilArrival: String {
        let minutes = Int((predictedArrivalTime ?? scheduledArrivalTime).timeIntervalSinceNow / 60)
        
        if minutes <= 0 {
            return "Due"
        } else if minutes == 1 {
            return "1 min"
        } else {
            return "\(minutes) min"
        }
    }
    
    // Check if the bus is late
    var isLate: Bool {
        guard let predictedTime = predictedArrivalTime else { return false }
        
        // Consider it late if it's more than 1 minute behind schedule
        let lateThreshold: TimeInterval = 60 // 1 minute
        return predictedTime.timeIntervalSince(scheduledArrivalTime) > lateThreshold
    }
    
    // Convert hex color to SwiftUI Color
    var routeColor: Color {
        Color(hex: routeColorHex) ?? .blue
    }
    
    // Example arrival for previews
    static var example: Arrival {
        Arrival(
            id: "1_10914_43",
            routeId: "1_43",
            routeShortName: "43",
            headsign: "Downtown Seattle",
            scheduledArrivalTime: Date().addingTimeInterval(600),
            predictedArrivalTime: Date().addingTimeInterval(540),
            routeColorHex: "#0077CC",
            tripId: "1_12345",
            status: "on_time"
        )
    }
    
    // Additional examples for testing and previews
    static var examples: [Arrival] {
        [
            Arrival(
                id: "1_10914_43",
                routeId: "1_43",
                routeShortName: "43",
                headsign: "Downtown Seattle",
                scheduledArrivalTime: Date().addingTimeInterval(600),
                predictedArrivalTime: Date().addingTimeInterval(540),
                routeColorHex: "#0077CC",
                tripId: "1_12345",
                status: "on_time"
            ),
            Arrival(
                id: "1_10914_49",
                routeId: "1_49",
                routeShortName: "49",
                headsign: "University District",
                scheduledArrivalTime: Date().addingTimeInterval(900),
                predictedArrivalTime: Date().addingTimeInterval(960),
                routeColorHex: "#CC0000",
                tripId: "1_23456",
                status: "delayed"
            ),
            Arrival(
                id: "1_10914_70",
                routeId: "1_70",
                routeShortName: "70",
                headsign: "Eastlake",
                scheduledArrivalTime: Date().addingTimeInterval(1200),
                predictedArrivalTime: nil,
                routeColorHex: "#00CC00",
                tripId: "1_34567",
                status: "scheduled"
            )
        ]
    }
}

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

