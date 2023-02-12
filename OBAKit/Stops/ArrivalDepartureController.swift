//
//  ArrivalDepartureController.swift
//  OBAKit
//
//  Created by Alan Chu on 2/11/23.
//

import SwiftUI
import OBAKitCore

class ArrivalDepartureController: ObservableObject {
    @MainActor @Published private(set) var arrivalDepartures: [ArrivalDepartureViewModel] = []
    private var stopArrivals: StopArrivals?

    @Published var minutesBefore: UInt = 10
    @Published var minutesAfter: UInt = 60

    private(set) var dateInterval: DateInterval?
    private(set) var lastUpdated: Date? {
        didSet {
            guard let lastUpdated else {
                return
            }

            dateInterval = DateInterval(
                start: lastUpdated.addingTimeInterval(-Double(minutesBefore * 60)),
                end: lastUpdated.addingTimeInterval(Double(minutesAfter  * 60))
            )
        }
    }

    let application: Application
    let stopID: StopID

    init(application: Application, stopID: StopID) {
        self.application = application
        self.stopID = stopID
    }

    private var lock: Bool = false
    func load() async {
        guard !lock else {
            return
        }

        lock = true
        defer {
            lock = false
        }

        guard let apiService = application.apiService else {
            return
        }

        let stopArrivals = try? await apiService.getArrivalsAndDeparturesForStop(id: stopID, minutesBefore: minutesBefore, minutesAfter: minutesAfter).entry

        await MainActor.run {
            lastUpdated = .now
        }

        guard let stopArrivals else {
            return
        }

        let newArrivalDepartures = stopArrivals.arrivalsAndDepartures.map(ArrivalDepartureViewModel.init)

        // todo: use OrderedDictionary?
        await MainActor.run {
            // Do simple diffing
            for new in newArrivalDepartures {
                let existingIndex = self.arrivalDepartures.firstIndex {
                    $0.id == new.id
                }

                if let existingIndex {
                    self.arrivalDepartures[existingIndex].update(with: new)
                } else {
                    // TODO: Insert by date
                    self.arrivalDepartures.append(new)
                }
            }
        }
    }
}
