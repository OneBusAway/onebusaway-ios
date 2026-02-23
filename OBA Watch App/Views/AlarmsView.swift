import SwiftUI
import OBAKitCore

struct AlarmsView: View {
    @State private var alarms: [WatchAlarmItem] = AlarmsSyncManager.shared.currentAlarms()
    var body: some View {
        List {
            if alarms.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(OBALoc("alarms.no_alarms", value: "No Alarms", comment: "Empty state title for alarms"))
                        .font(.headline)
                }
                .padding()
            } else {
                ForEach(alarms) { alarm in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(alarm.routeShortName ?? OBALoc("alarms.default_title", value: "Alarm", comment: "Default title for an alarm"))
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
                                // TODO: Implement DeepLinkSyncManager in PR3/PR4
                                // DeepLinkSyncManager.shared.openStopOnPhone(stopID: alarm.stopID)
                            } label: {
                                Image(systemName: "iphone")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(OBALoc("alarms.title", value: "Alarms", comment: "Title for alarms screen"))
        .onReceive(NotificationCenter.default.publisher(for: AlarmsSyncManager.alarmsUpdatedNotification)) { _ in
            alarms = AlarmsSyncManager.shared.currentAlarms()
        }
    }
}


#Preview {
    AlarmsView()
}
