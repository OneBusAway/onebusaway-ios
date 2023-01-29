//
//  RegionPickerMap.swift
//  OBAKit
//
//  Created by Alan Chu on 1/14/23.
//

import SwiftUI
import MapKit

/// A collapsible Map.
struct RegionPickerMap: View {
    @Binding var mapRect: MKMapRect?

    @State var mapHeight: CGFloat = 300
    @State var isMapExpanded: Bool = true

    var body: some View {
        ZStack {
            Button {
                withAnimation {
                    isMapExpanded.toggle()
                }
            } label: {
                Label("Show Map", systemImage: "chevron.compact.up")
                    .labelStyle(.iconOnly)
                    .imageScale(.large)
                    .font(.headline.weight(.heavy))
                    .frame(maxWidth: .infinity)
            }
            .padding(.top)
            .disabled(mapRect == nil)
            .opacity(isMapExpanded ? 0 : 1)

            if let mapRect, isMapExpanded {
                Map(
                    mapRect: .constant(mapRect),
                    interactionModes: [],
                    showsUserLocation: false,
                    userTrackingMode: .none
                )
                .cornerRadius(24)
                .transition(
                    .move(edge: .bottom)
                    .combined(with: .opacity)
                )
                .frame(maxWidth: .infinity, minHeight: mapHeight, maxHeight: mapHeight, alignment: .top)
                .onTapGesture {
                    withAnimation {
                        isMapExpanded.toggle()
                    }
                }
                .highPriorityGesture(
                    DragGesture()
                        .onChanged { gesture in
                            // Swipe down gesture to dismiss map.
                            if gesture.translation.height > 50 {
                                withAnimation {
                                    isMapExpanded = false
                                }
                            }
                        }
                )
            }
        }
    }
}

struct RegionPickerMap_Previews: PreviewProvider {
    static let pugetSound: MKMapRect = MKMapRect(origin: MKMapPoint(CLLocationCoordinate2D(latitude: 48.643, longitude: -123.3964)), size: MKMapSize(width: 1338771.0533083975, height: 1897888.1099742651))

    static var previews: some View {
        RegionPickerMap(mapRect: .constant(pugetSound))
    }
}
