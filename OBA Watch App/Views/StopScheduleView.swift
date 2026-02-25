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
                DatePicker(OBALoc("schedule.date", value: "Date", comment: "Date picker label"), selection: $date, displayedComponents: .date)
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
                Section(String(format: OBALoc("schedule.stop_fmt", value: "Stop %@", comment: "Stop header format"), schedule.stopID)) {
                    ForEach(schedule.stopTimes.indices, id: \.self) { idx in
                        let t = schedule.stopTimes[idx]
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.tripID)
                                .font(.subheadline)
                            HStack {
                                Text(String(format: OBALoc("schedule.arrival_fmt", value: "Arr: %@", comment: "Arrival time format"), DateFormatterHelper.timeFormatter.string(from: t.arrivalTime)))
                                Spacer()
                                Text(String(format: OBALoc("schedule.departure_fmt", value: "Dep: %@", comment: "Departure time format"), DateFormatterHelper.timeFormatter.string(from: t.departureTime)))
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
        .navigationTitle(OBALoc("schedule.title", value: "Schedule", comment: "Schedule title"))
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
