//
//  TripArrivalView.swift
//  OBAKit
//
//  Created by Alan Chu on 2/9/23.
//

import SwiftUI
import OBAKitCore

struct TripArrivalVieww: View {
    @ObservedObject var viewModel: ArrivalDepartureViewModel

    @State var deemphasizePastTrips: Bool = true

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(viewModel.routeAndHeadsign)
                    .font(.headline)
                StopArrivalExplanationView(
                    arrivalDepartureDate: viewModel.arrivalDepartureDate,
                    scheduleStatus: viewModel.scheduleStatus,
                    temporalState: viewModel.temporalState,
                    arrivalDepartureStatus: viewModel.arrivalDepartureStatus,
                    scheduleDeviationInMinutes: viewModel.scheduleDeviationInMinutes
                )
                    .font(.subheadline)
            }

            Spacer()

            DepartureTimeBadgeView(
                date: $viewModel.arrivalDepartureDate,
                temporalState: $viewModel.temporalState,
                scheduleStatus: $viewModel.scheduleStatus)
        }
        .opacity(deemphasizePastTrips && viewModel.temporalState == .past ? 0.3 : 1.0)
    }
}

#if DEBUG
struct TripArrivalVieww_Previews: PreviewProvider {
    static var previews: some View {
        List {
            ForEach(ArrivalDepartureViewModel.all) { tripArrival in
                TripArrivalVieww(viewModel: tripArrival)
            }
        }
    }
}
#endif
