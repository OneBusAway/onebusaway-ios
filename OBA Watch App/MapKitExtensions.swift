import Foundation
import MapKit
import CoreLocation

extension MKPlacemark {
    var mkCoordinateRegion: MKCoordinateRegion? {
        guard let boundingRegion = self.region as? CLCircularRegion else { return nil }
        return MKCoordinateRegion(center: boundingRegion.center, latitudinalMeters: 2000.0, longitudinalMeters: 2000.0)
    }
}

extension CLCircularRegion {
    func toMKMapRect() -> MKMapRect {
        let radius = self.radius
        let center = self.center
        
        let latDelta = radius / 111320.0
        let lonDelta = radius / (111320.0 * cos(center.latitude * .pi / 180.0))
        
        let northWest = CLLocationCoordinate2D(latitude: center.latitude + latDelta, longitude: center.longitude - lonDelta)
        let southEast = CLLocationCoordinate2D(latitude: center.latitude - latDelta, longitude: center.longitude + lonDelta)
        
        let nwPoint = MKMapPoint(northWest)
        let sePoint = MKMapPoint(southEast)
        
        return MKMapRect(
            x: min(nwPoint.x, sePoint.x),
            y: min(nwPoint.y, sePoint.y),
            width: abs(nwPoint.x - sePoint.x),
            height: abs(nwPoint.y - sePoint.y)
        )
    }
}
