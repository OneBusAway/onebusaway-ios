//
//  TripArrivalView.swift
//  OBAKit
//
//  Created by Alan Chu on 2/9/23.
//

import SwiftUI
import OBAKitCore

struct TripArrivalVieww: View {
    var viewModel: TripArrivalViewModel

    @State var deemphasizePastTrips: Bool = true

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(viewModel.routeAndHeadsign)
                    .font(.headline)
                StopArrivalExplanationView(
                    arrivalDepartureDate: viewModel.date,
                    scheduleStatus: viewModel.scheduleStatus,
                    temporalState: viewModel.temporalState,
                    arrivalDepartureStatus: viewModel.arrivalDepartureStatus,
                    scheduleDeviationInMinutes: viewModel.scheduleDeviationInMinutes
                )
                    .font(.subheadline)
            }

            Spacer()

            DepartureTimeBadgeView(date: viewModel.date, temporalState: viewModel.temporalState, scheduleStatus: viewModel.scheduleStatus)
        }
        .opacity(deemphasizePastTrips && viewModel.temporalState == .past ? 0.3 : 1.0)
    }
}

#if DEBUG
struct TripArrivalVieww_Previews: PreviewProvider {
    static var previews: some View {
        List {
            ForEach(TripArrivalViewModel.all) { tripArrival in
                TripArrivalVieww(viewModel: tripArrival)
            }
        }
    }
}
#endif
