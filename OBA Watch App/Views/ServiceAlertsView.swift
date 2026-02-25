import SwiftUI
import OBAKitCore

struct ServiceAlertsView: View {
    @State private var alerts: [WatchServiceAlert] = ServiceAlertsSyncManager.shared.currentAlerts()
    var body: some View {
        List {
            if alerts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(OBALoc("alerts.empty.title", value: "No Notifications", comment: "No alerts title"))
                        .font(.headline)
                    Text(OBALoc("alerts.empty.subtitle", value: "No active notifications", comment: "No alerts subtitle"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                ForEach(alerts) { alert in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(alert.title)
                            .font(.headline)
                        if let body = alert.body, !body.isEmpty {
                            Text(body)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        HStack {
                            if let severity = alert.severity, !severity.isEmpty {
                                Text(severity)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                DeepLinkSyncManager.shared.openAlertsOnPhone()
                            } label: {
                                Image(systemName: "iphone")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Notifications")
        .onReceive(NotificationCenter.default.publisher(for: ServiceAlertsSyncManager.alertsUpdatedNotification)) { _ in
            alerts = ServiceAlertsSyncManager.shared.currentAlerts()
        }
    }
}
