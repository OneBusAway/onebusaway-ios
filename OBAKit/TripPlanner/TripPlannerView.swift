//
//  TripPlannerView.swift
//  OBAKit
//
//  Created by Hilmy Veradin on 14/09/24.
//

import MapKit
import OTPKit
import SwiftUI

struct TripPlannerView: View {
    @Environment(TripPlannerService.self) private var tripPlanner

    var body: some View {
        ZStack {
            TripPlannerExtensionView {
                Map(position: tripPlanner.currentCameraPositionBinding, interactionModes: .all) {
                    tripPlanner.generateMarkers()
                    tripPlanner.generateMapPolyline()
                        .stroke(.blue, lineWidth: 5)
                }
                .mapControls {
                    if !tripPlanner.isMapMarkingMode {
                        MapUserLocationButton()
                        MapPitchToggle()
                    }
                }
            }
        }

    }
}

#Preview {
    TripPlannerView()
}
