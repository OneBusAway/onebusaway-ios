import SwiftUI
import OBAKitCore

struct VehicleRow: View {
    let vehicleID: String
    let routeShortName: String?
    let tripHeadsign: String?
    let lastUpdateTime: Date?
    let status: String?
    let phase: String?
    let tripID: String?
    let latitude: Double?
    let longitude: Double?
    
    init(
        vehicleID: String,
        routeShortName: String?,
        tripHeadsign: String?,
        lastUpdateTime: Date?,
        status: String?,
        phase: String?,
        tripID: String?,
        latitude: Double?,
        longitude: Double?
    ) {
        self.vehicleID = vehicleID
        self.routeShortName = routeShortName
        self.tripHeadsign = tripHeadsign
        self.lastUpdateTime = lastUpdateTime
        self.status = status
        self.phase = phase
        self.tripID = tripID
        self.latitude = latitude
        self.longitude = longitude
    }

    private var displayVehicleID: String {
        let id = vehicleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (tripID ?? "Unknown") : vehicleID
        return id.replacingOccurrences(of: " ", with: "\n")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Bus Icon on the left
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 28, height: 28)
                
                Image(systemName: "bus.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                // Clean, Semibold Vehicle ID - even smaller
                Text(displayVehicleID)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                if let status = status, !status.isEmpty {
                    Text(status.capitalized)
                        .font(.system(size: 12))
                        .foregroundColor(statusColor(status))
                }
            }
            
            Spacer()
            
            // Time on the right
            if let lastUpdate = lastUpdateTime {
                Text(formatTime(lastUpdate))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
    }
    
    private func statusColor(_ status: String) -> Color {
        let s = status.lowercased()
        if s.contains("on time") || s.contains("on_time") { return .green }
        if s.contains("late") || s.contains("delayed") { return .red }
        if s.contains("early") { return .yellow }
        return .secondary
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

#if DEBUG
struct VehicleRow_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            VehicleRow(
                vehicleID: "1_1234",
                routeShortName: "10",
                tripHeadsign: "Downtown Seattle",
                lastUpdateTime: Date(),
                status: "ON TIME",
                phase: "in_progress",
                tripID: "1_987654",
                latitude: 47.6062,
                longitude: -122.3321
            )
            
            VehicleRow(
                vehicleID: "1_5678",
                routeShortName: nil,
                tripHeadsign: nil,
                lastUpdateTime: Date().addingTimeInterval(-60),
                status: nil,
                phase: nil,
                tripID: nil,
                latitude: nil,
                longitude: nil
            )
        }
    }
}
#endif
