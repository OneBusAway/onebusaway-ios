//
//  StopArrivalHeaderView.swift
//  OBAKit
//
//  Created by Alan Chu on 2/22/23.
//

import MapKit
import SwiftUI

struct StopArrivalHeaderView: View {
    @Environment(\.stopIconFactory) var stopIconFactory

    @State var region: MKCoordinateRegion
    @State var mapImage: UIImage?

    var body: some View {
        ZStack {
            Map(coordinateRegion: $region, interactionModes: [])
            Text("asdf")

            if let mapImage {
                Image(uiImage: mapImage)
            }
        }
        .task(priority: .high) {
//            stopIconFactory.buildIcon(for: <#T##Stop#>, isBookmarked: <#T##Bool#>, traits: <#T##UITraitCollection#>)
//            let snapshot = MapSnapshotter(size: , stopIconFactory: <#T##StopIconFactory#>)
        }
    }
}

struct StopArrivalHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        StopArrivalHeaderView(
            region: MapHelpers.coordinateRegionWith(
                center: CLLocationCoordinate2D(latitude: 47.62217, longitude: -122.32090),
                zoomLevel: 16,
                size: CGSize(width: 375, height: 250)
            )
        )
        .frame(width: 375, height: 250, alignment: .center)
        .previewLayout(.sizeThatFits)
    }
}
