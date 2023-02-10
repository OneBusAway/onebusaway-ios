//
//  StopArrivalsView.swift
//  OBAKit
//
//  Created by Alan Chu on 2/10/23.
//

import SwiftUI
import OBAKitCore

struct StopArrivalsView: View {
    @Environment(\.coreApplication) var application

    var stopID: StopID

    @State var error: Error?

    @State var isLoading: Bool = true
    @State var minutesBefore: UInt = 10
    @State var minutesAfter: UInt = 60

    @State var arrivalDepartures: [TripArrivalViewModel] = []
    @State var selectedItem: TripArrivalViewModel?

    var body: some View {
        List {
            Section {
                if isLoading {
                    loading
                } else if arrivalDepartures.isEmpty {
                    empty
                } else {
                    ForEach(arrivalDepartures) { arrDep in
                        NavigationLink {
                            Text(arrDep.routeAndHeadsign)
                        } label: {
                            TripArrivalVieww(viewModel: arrDep)
                        }
                    }
//                    Picker("", selection: $selectedItem) {
//                        ForEach(arrivalDepartures, id: \.self) { arrivalDeparture in
////                            TripArrivalVieww(viewModel: arrivalDeparture)
////                                .tag(Optional(arrivalDeparture))
//                        }
//                    }
//                    .pickerStyle(.inline)
//                    .labelsHidden()

                }
            } footer: {
                Text("Selected \(selectedItem?.routeAndHeadsign ?? "N/A")")
            }
        }
        .refreshable {
            guard !isLoading else {
                return
            }

            isLoading = true
        }
        .task(id: isLoading, priority: .userInitiated) {
            guard isLoading, let apiService = application.apiService else {
                return
            }

//            try? await Task.sleep(nanoseconds: 2_000_000_000)

            let stopArrivals: StopArrivals
            do {
                stopArrivals = try await apiService.getArrivalsAndDeparturesForStop(id: stopID, minutesBefore: minutesBefore, minutesAfter: minutesAfter).entry
            } catch {
                await MainActor.run {
                    self.error = error
                }

                return
            }

            let viewModels = stopArrivals.arrivalsAndDepartures.map(TripArrivalViewModel.fromArrivalDeparture)

            await MainActor.run {
                self.arrivalDepartures = viewModels
            }

            self.isLoading = false
        }
    }

    var empty: some View {
        Text("No data")
            .multilineTextAlignment(.center)
    }

    var loading: some View {
        ForEach(0..<5) { _ in
            TripArrivalVieww(viewModel: .loadingIndicator)
        }
        .redacted(reason: .placeholder)
    }
}
