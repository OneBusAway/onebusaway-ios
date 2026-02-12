//
//  TripArrivalView.swift
//  OBAKit
//
//  Created by Alan Chu on 2/9/23.
//

import SwiftUI
import OBAKitCore

/// A view that tracks an `ArrivalDeparture`.
struct ArrivalDepartureView: View {
    @ObservedObject var viewObject: ArrivalDepartureViewObject

    @State var deemphasizePastTrips: Bool = true

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(viewObject.routeAndHeadsign)
                    .font(.headline)
                StopArrivalExplanationView(
                    arrivalDepartureDate: viewObject.arrivalDepartureDate,
                    scheduleStatus: viewObject.scheduleStatus,
                    temporalState: viewObject.temporalState,
                    arrivalDepartureStatus: viewObject.arrivalDepartureStatus,
                    scheduleDeviationInMinutes: viewObject.scheduleDeviationInMinutes
                )
                    .font(.subheadline)
            }

            Spacer()

            DepartureTimeBadgeView(
                date: $viewObject.arrivalDepartureDate,
                temporalState: $viewObject.temporalState,
                scheduleStatus: $viewObject.scheduleStatus)
        }
        .opacity(deemphasizePastTrips && viewObject.temporalState == .past ? 0.3 : 1.0)
    }
}

#if DEBUG
struct TripArrivalVieww_Previews: PreviewProvider {
    static var previews: some View {
        List {
            ForEach(ArrivalDepartureViewObject.all) { tripArrival in
                ArrivalDepartureView(viewObject: tripArrival)
            }
        }
    }
}
#endif
