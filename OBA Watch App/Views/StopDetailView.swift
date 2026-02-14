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
                            Text("Stop \(code)")
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
                Section("Location") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "Lat: %.5f", stop.latitude))
                        Text(String(format: "Lon: %.5f", stop.longitude))
                    }
                    .font(.caption)
                }
            }
        }
        .navigationTitle("Stop")
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
