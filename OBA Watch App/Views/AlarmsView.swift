import SwiftUI

struct AlarmsView: View {
    @State private var alarms: [AlarmItem] = AlarmsSyncManager.shared.currentAlarms()
    var body: some View {
        List {
            if alarms.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No Alarms")
                        .font(.headline)
                }
                .padding()
            } else {
                ForEach(alarms) { alarm in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(alarm.routeShortName ?? "Alarm")
                            .font(.headline)
                        if let headsign = alarm.headsign, !headsign.isEmpty {
                            Text(headsign)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            if let status = alarm.status {
                                Text(status)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                DeepLinkSyncManager.shared.openStopOnPhone(stopID: alarm.stopID)
                            } label: {
                                Image(systemName: "iphone")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Alarms")
        .onReceive(NotificationCenter.default.publisher(for: AlarmsSyncManager.alarmsUpdatedNotification)) { _ in
            alarms = AlarmsSyncManager.shared.currentAlarms()
        }
    }
}


#Preview {
    AlarmsView()
}
