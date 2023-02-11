//
//  ArrivalDepartureController.swift
//  OBAKit
//
//  Created by Alan Chu on 2/11/23.
//

import SwiftUI
import OBAKitCore

class ArrivalDepartureController: ObservableObject {
    struct ArrivalDepartureIdentifier: Hashable {
        let tripID: TripIdentifier
        let routeID: RouteID
        let stopID: StopID
        let serviceDate: Date
    }

    class ArrivalDepartureObject: Identifiable, ObservableObject/*, Comparable*/ {
        let id: ArrivalDepartureIdentifier

        @Published var routeAndHeadsign: String

        @Published var arrivalDepartureDate: Date
        @Published var arrivalDepartureStatus: ArrivalDepartureStatus
        @Published var temporalState: TemporalState
        @Published var scheduleStatus: ScheduleStatus
        @Published var scheduleDeviationInMinutes: Int

        @MainActor
        func update(with newValues: ArrivalDepartureObject) {
            precondition(newValues.id == self.id)

            self.routeAndHeadsign = newValues.routeAndHeadsign
            self.arrivalDepartureDate = newValues.arrivalDepartureDate
            self.arrivalDepartureStatus = newValues.arrivalDepartureStatus
            self.temporalState = newValues.temporalState
            self.scheduleStatus = newValues.scheduleStatus
            self.scheduleDeviationInMinutes = newValues.scheduleDeviationInMinutes
        }

        @objc func debugQuickLookObject() -> Any? {
            "Date: \(arrivalDepartureDate)\nStatus: \(arrivalDepartureStatus)\nState: \(temporalState)"
        }

        init(_ arrivalDeparture: ArrivalDeparture) {
            self.id = ArrivalDepartureIdentifier(tripID: arrivalDeparture.tripID, routeID: arrivalDeparture.routeID, stopID: arrivalDeparture.stopID, serviceDate: arrivalDeparture.serviceDate)

            self.routeAndHeadsign = arrivalDeparture.routeAndHeadsign
            self.arrivalDepartureDate = arrivalDeparture.arrivalDepartureDate
            self.arrivalDepartureStatus = arrivalDeparture.arrivalDepartureStatus
            self.temporalState = arrivalDeparture.temporalState
            self.scheduleStatus = arrivalDeparture.scheduleStatus
            self.scheduleDeviationInMinutes = arrivalDeparture.deviationFromScheduleInMinutes
        }
    }

    @MainActor @Published private(set) var arrivalDepartures: [ArrivalDepartureObject] = []
    @Published var minutesBefore: UInt = 10
    @Published var minutesAfter: UInt = 60
    @Published private(set) var lastUpdated: Date?

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

        guard let stopArrivals else {
            return
        }

        let newArrivalDepartures = stopArrivals.arrivalsAndDepartures.map(ArrivalDepartureObject.init)

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
