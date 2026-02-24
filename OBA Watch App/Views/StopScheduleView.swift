import SwiftUI
import OBAKitCore

struct StopScheduleView: View {
    let stopID: OBAStopID
    @State private var date: Date = Date()
    @State private var schedule: OBAStopSchedule?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .onChange(of: date) { _, _ in
                        Task { await load() }
                    }
            }
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
            } else if let schedule {
                Section("Stop \(schedule.stopID)") {
                    ForEach(schedule.stopTimes.indices, id: \.self) { idx in
                        let t = schedule.stopTimes[idx]
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.tripID)
                                .font(.subheadline)
                            HStack {
                                Text("Arr: \(DateFormatterHelper.timeFormatter.string(from: t.arrivalTime))")
                                Spacer()
                                Text("Dep: \(DateFormatterHelper.timeFormatter.string(from: t.departureTime))")
                            }
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            if let h = t.stopHeadsign, !h.isEmpty {
                                Text(h)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Schedule")
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
            let s = try await WatchAppState.shared.apiClient.fetchScheduleForStop(stopID: stopID, date: date)
            schedule = s
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
