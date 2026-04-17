import SwiftUI
import CoreLocation

struct ItineraryListView: View {
    let itineraries: [OTPItinerary]
    
    var body: some View {
        List {
            ForEach(itineraries) { itinerary in
                NavigationLink(destination: ItineraryDetailView(itinerary: itinerary)) {
                    ItineraryRow(itinerary: itinerary)
                }
            }
        }
        .navigationTitle(OBALoc("itinerary.title", value: "Routes", comment: "Itineraries title"))
    }
}

struct ItineraryRow: View {
    let itinerary: [OTPItinerary].Element
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(formatTime(itinerary.startTime))
                    .font(.headline)
                Image(systemName: "arrow.right")
                    .font(.caption)
                Text(formatTime(itinerary.endTime))
                    .font(.headline)
            }
            
            HStack {
                ForEach(itinerary.legs.prefix(4)) { leg in
                    LegIcon(mode: leg.mode)
                }
                if itinerary.legs.count > 4 {
                    Text("+")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(formatDuration(itinerary.duration))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        return "\(minutes) min"
    }
}

struct LegIcon: View {
    let mode: String
    
    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 10))
            .padding(4)
            .background(backgroundColor.opacity(0.2))
            .cornerRadius(4)
            .foregroundColor(backgroundColor)
    }
    
    private var iconName: String {
        switch mode.uppercased() {
        case "WALK": return "figure.walk"
        case "BUS": return "bus"
        case "RAIL", "SUBWAY", "TRAM": return "train.side.front.car"
        default: return "questionmark"
        }
    }
    
    private var backgroundColor: Color {
        switch mode.uppercased() {
        case "WALK": return .gray
        case "BUS": return .green
        case "RAIL", "SUBWAY", "TRAM": return .blue
        default: return .secondary
        }
    }
}
