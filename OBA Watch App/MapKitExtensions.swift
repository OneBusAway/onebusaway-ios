import Foundation
import MapKit
import CoreLocation

extension MKCoordinateRegion {
    init(_ mapRect: MKMapRect) {
        let centerCoordinate = MKMapPoint(x: mapRect.midX, y: mapRect.midY).coordinate
        let span = MKCoordinateSpan(latitudeDelta: mapRect.size.height, longitudeDelta: mapRect.size.width)
        self.init(center: centerCoordinate, span: span)
    }
}

extension MKPlacemark {
    var mkCoordinateRegion: MKCoordinateRegion? {
        guard let boundingRegion = self.region as? CLCircularRegion else { return nil }
        return MKCoordinateRegion(center: boundingRegion.center, latitudinalMeters: 2000.0, longitudinalMeters: 2000.0)
    }
}

extension CLCircularRegion {
    func toMKMapRect() -> MKMapRect {
        let center = self.center
        let coordinateRegion = MKCoordinateRegion(center: center, latitudinalMeters: 2000.0, longitudinalMeters: 2000.0)
        let mapPoint = MKMapPoint(coordinateRegion.center)
        let mapSize = MKMapSize(width: coordinateRegion.span.longitudeDelta * 111320.0, height: coordinateRegion.span.latitudeDelta * 111320.0) // Approximation
        return MKMapRect(origin: MKMapPoint(x: mapPoint.x - mapSize.width / 2, y: mapPoint.y - mapSize.height / 2), size: mapSize)
    }
}
