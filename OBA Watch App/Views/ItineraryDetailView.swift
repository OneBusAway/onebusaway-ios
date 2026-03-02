import SwiftUI

struct ItineraryDetailView: View {
    let itinerary: OTPItinerary
    
    var body: some View {
        List {
            Section(header: Text(OBALoc("itinerary.section.summary", value: "Summary", comment: "Itinerary summary section header"))) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(OBALoc("itinerary.label.duration", value: "Duration", comment: "Itinerary duration label"))
                        Spacer()
                        Text(formatDuration(itinerary.duration))
                    }
                    HStack {
                        Text(OBALoc("itinerary.label.walk_time", value: "Walk Time", comment: "Itinerary walk time label"))
                        Spacer()
                        Text(formatDuration(itinerary.walkTime))
                    }
                    HStack {
                        Text(OBALoc("itinerary.label.transfers", value: "Transfers", comment: "Itinerary transfers label"))
                        Spacer()
                        Text("\(itinerary.transfers)")
                    }
                }
                .font(.caption)
            }
            
            Section(header: Text(OBALoc("itinerary.section.directions", value: "Directions", comment: "Itinerary directions section header"))) {
                ForEach(itinerary.legs) { leg in
                    LegDetailRow(leg: leg)
                }
            }
        }
        .navigationTitle(OBALoc("itinerary.nav_title", value: "Details", comment: "Itinerary detail navigation title"))
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        return "\(minutes) min"
    }
}

struct LegDetailRow: View {
    let leg: OTPLeg
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(backgroundColor)
                
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.caption)
                        .bold()
                    
                    if let headsign = leg.headsign {
                        Text(String(format: OBALoc("itinerary.leg.to_headsign_fmt", value: "to %@", comment: "Direction: to [headsign]"), headsign))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            HStack {
                Text(formatTime(leg.startTime))
                Image(systemName: "arrow.right")
                Text(formatTime(leg.endTime))
                
                Spacer()
                
                Text(formatDuration(leg.duration))
            }
            .font(.system(size: 9))
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
    
    private var title: String {
        if leg.mode.uppercased() == "WALK" {
            return String(format: OBALoc("itinerary.leg.walk_format", value: "Walk %dm", comment: "Walk distance format"), Int(leg.distance))
        } else {
            return "\(leg.routeShortName ?? leg.mode) - \(leg.from.name)"
        }
    }
    
    private var iconName: String {
        switch leg.mode.uppercased() {
        case "WALK": return "figure.walk"
        case "BUS": return "bus"
        case "RAIL", "SUBWAY", "TRAM": return "train.side.front.car"
        default: return "questionmark"
        }
    }
    
    private var backgroundColor: Color {
        switch leg.mode.uppercased() {
        case "WALK": return .gray
        case "BUS": return .green
        case "RAIL", "SUBWAY", "TRAM": return .blue
        default: return .secondary
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        return "\(minutes)m"
    }
}
