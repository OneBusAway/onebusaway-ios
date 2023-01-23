//
//  Region+Previews.swift
//  OBAKit
//
//  Created by Alan Chu on 1/20/23.
//

import MapKit
import OBAKitCore

#if DEBUG

extension Region {
    static func regionForPreview(
        id: RegionIdentifier,
        name: String,
        latitude: CLLocationDegrees,
        longitude: CLLocationDegrees,
        latitudeSpan: CLLocationDegrees,
        longitudeSpan: CLLocationDegrees
    ) -> Region {

        let origin = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let span = MKCoordinateSpan(latitudeDelta: latitudeSpan, longitudeDelta: longitudeSpan)
        let region = MKCoordinateRegion(center: origin, span: span)

        return self.init(name: name, OBABaseURL: URL(string: "www.example.com")!, coordinateRegion: region, contactEmail: "example@example.com", regionIdentifier: id)
    }
}

#endif
