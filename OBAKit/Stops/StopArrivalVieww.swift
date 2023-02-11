//
//  TripArrivalView.swift
//  OBAKit
//
//  Created by Alan Chu on 2/9/23.
//

import SwiftUI
import OBAKitCore

struct TripArrivalVieww: View {
    @ObservedObject var object: ArrivalDepartureController.ArrivalDepartureObject

    @State var deemphasizePastTrips: Bool = true

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(object.routeAndHeadsign)
                    .font(.headline)
                StopArrivalExplanationView(
                    arrivalDepartureDate: object.arrivalDepartureDate,
                    scheduleStatus: object.scheduleStatus,
                    temporalState: object.temporalState,
                    arrivalDepartureStatus: object.arrivalDepartureStatus,
                    scheduleDeviationInMinutes: object.scheduleDeviationInMinutes
                )
                    .font(.subheadline)
            }

            Spacer()

            DepartureTimeBadgeView(
                date: $object.arrivalDepartureDate,
                temporalState: $object.temporalState,
                scheduleStatus: $object.scheduleStatus)
        }
        .opacity(deemphasizePastTrips && object.temporalState == .past ? 0.3 : 1.0)
    }
}

#if DEBUG
//struct TripArrivalVieww_Previews: PreviewProvider {
//    static var previews: some View {
//        List {
//            ForEach(TripArrivalViewModel.all) { tripArrival in
//                TripArrivalVieww(viewModel: tripArrival)
//            }
//        }
//    }
//}
#endif
