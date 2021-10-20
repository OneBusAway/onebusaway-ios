//
//  TripBookmarkView.swift
//  OBAKit
//
//  Created by Alan Chu on 10/5/21.
//

import SwiftUI
import OBAKitCore

struct TripBookmarkView: View {
    @Environment(\.obaFormatters) var formatters
    @State var viewModel: TripBookmarkViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
//            if let routeShortName = viewModel.routeShortName {
//                RouteTypeLabelView(labelText: routeShortName, routeType: viewModel.routeType)
//            }

            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    Text(viewModel.name)
                        .font(.headline)

                    if let headlineArrDep = viewModel.primaryArrivalDeparture {
                        headline(headlineArrDep)
                    } else {
                        Text("No upcoming trips.")
                            .font(.caption)
                    }

                    Spacer()
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if let first = viewModel.primaryArrivalDeparture {
                        DepartureTimeView(viewModel: first, isBadge: true)
                            .fixedSize()
                    }

                    if let second = viewModel.secondaryArrivalDeparture {
                        DepartureTimeView(viewModel: second, isBadge: false)
                    }

                    if let third = viewModel.tertiaryArrivalDeparture {
                        DepartureTimeView(viewModel: third, isBadge: false)
                    }
                }
            }
        }
    }

    func headline(_ arrDep: DepartureTimeViewModel) -> some View {
        let now = Calendar.current.dateComponents([.day, .hour, .minute], from: Date())
        let arrDepDate = Calendar.current.dateComponents([.day, .hour, .minute], from: arrDep.arrivalDepartureDate)
        let deviation = Calendar.current.dateComponents([.minute], from: arrDepDate, to: now).minute ?? 0

        return formatters.fullAttributedArrivalDepartureExplanation(arrivalDepartureDate: arrDep.arrivalDepartureDate, scheduleStatus: arrDep.scheduleStatus, temporalState: arrDep.temporalState, arrivalDepartureStatus: arrDep.arrivalDepartureStatus, scheduleDeviationInMinutes: deviation)
    }
}

struct TripBookmarkView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            List {
                TripBookmarkView(viewModel: .linkArrivingNowOnTime)
                TripBookmarkView(viewModel: .metroTransitBLineDepartingLate)
                TripBookmarkView(viewModel: .soundTransit550NoTrips)
            }.listStyle(.plain)
        }
    }
}
