import SwiftUI
import OBAKitCore
import CoreLocation

struct StopDetailView: View {
    let stopID: OBAStopID
    @State private var stop: OBAStop?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            } else if let stop {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stop.name)
                            .font(.headline)
                        if let code = stop.code, !code.isEmpty {
                            Text(String(format: OBALoc("stop_details.stop_code_fmt", value: "Stop %@", comment: "Stop code format"), code))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let dir = stop.direction, !dir.isEmpty {
                            Text(dir)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Section(OBALoc("common.location", value: "Location", comment: "Section title for location")) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: OBALoc("stop_details.lat_fmt", value: "Lat: %.5f", comment: "Latitude format"), stop.latitude))
                        Text(String(format: OBALoc("stop_details.lon_fmt", value: "Lon: %.5f", comment: "Longitude format"), stop.longitude))
                    }
                    .font(.caption)
                }
            }
        }
        .navigationTitle(OBALoc("stop_details.title_short", value: "Stop", comment: "Short title for stop details"))
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let s = try await WatchAppState.shared.apiClient.fetchStop(id: stopID)
            stop = s
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
