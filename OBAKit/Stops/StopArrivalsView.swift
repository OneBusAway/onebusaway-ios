//
//  StopArrivalsView.swift
//  OBAKit
//
//  Created by Alan Chu on 2/10/23.
//

import SwiftUI
import OBAKitCore

struct StopArrivalsView: View {
    @ObservedObject var controller: ArrivalDepartureController

    init(_ application: Application, stopID: StopID) {
        self.controller = ArrivalDepartureController(application: application, stopID: stopID)
    }

    @State var isLoading: Bool = true
    @State var selectedItem: ArrivalDeparture.Identifier?

    var body: some View {
        List {
            Section {
                if isLoading && controller.arrivalDepartures.isEmpty {
                    loading
                } else if controller.arrivalDepartures.isEmpty {
                    empty
                    loadMore
                } else {
                    arrivalDeparturesView
                    loadMore
                }
            } footer: {
                Text("Selected \(String(describing: selectedItem))")
            }
        }
        .onAppear {
            selectedItem = nil
        }
        .refreshable {
            guard !isLoading else {
                return
            }

            isLoading = true
        }
        .task(id: isLoading, priority: .userInitiated) {
            guard isLoading else {
                return
            }

            await controller.load()
            isLoading = false
        }
    }

    var empty: some View {
        Text("No data")
            .multilineTextAlignment(.center)
    }

    var loading: some View {
        Text("Loading")
//        ForEach(0..<5) { _ in
//            TripArrivalVieww(viewModel: .loadingIndicator)
//        }
//        .redacted(reason: .placeholder)
    }

    // MARK: - Has data content
    var arrivalDeparturesView: some View {
        ForEach(controller.arrivalDepartures) { arrDep in
            ArrivalDepartureView(viewObject: arrDep)
                .onListSelection {
                    if selectedItem == arrDep.id {
                        selectedItem = nil
                    } else {
                        selectedItem = arrDep.id
                    }
                }
                .listRowBackground(selectedItem == arrDep.id ? Color(UIColor.systemGroupedBackground) : nil)
                .contextMenu {
                    Button("asdf", action: {})
                }
        }
    }

    @ViewBuilder
    var loadMore: some View {
        VStack(alignment: .leading) {
            Button("Load More") {
                self.controller.minutesAfter += 30
                self.isLoading = true
            }
            .disabled(isLoading)

            timeRange
        }
    }

    @ViewBuilder
    var timeRange: some View {
        if let dateInterval = controller.dateInterval {
            Text(dateInterval)
        }
    }
}
