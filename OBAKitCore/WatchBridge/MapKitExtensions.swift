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
        let radius = self.radius
        let coordinateRegion = MKCoordinateRegion(center: center, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        let mapPoint = MKMapPoint(coordinateRegion.center)
        let mapSize = MKMapSize(width: coordinateRegion.span.longitudeDelta * 111320.0, height: coordinateRegion.span.latitudeDelta * 111320.0) // Approximation
        return MKMapRect(origin: MKMapPoint(x: mapPoint.x - mapSize.width / 2, y: mapPoint.y - mapSize.height / 2), size: mapSize)
    }
}

extension AgencyRegionBound {
    public var serviceRect: MKMapRect {
        let centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let latitudinalMeters = latSpan * 111320.0 // Approximation for degrees latitude to meters
        let longitudinalMeters = lonSpan * 111320.0 * cos(lat * .pi / 180.0) // Approximation for degrees longitude to meters

        let region = MKCoordinateRegion(center: centerCoordinate, latitudinalMeters: latitudinalMeters, longitudinalMeters: longitudinalMeters)

        let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta / 2, longitude: region.center.longitude - region.span.longitudeDelta / 2))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta / 2, longitude: region.center.longitude + region.span.longitudeDelta / 2))

        return MKMapRect(x: min(topLeft.x, bottomRight.x), y: min(topLeft.y, bottomRight.y), width: abs(topLeft.x - bottomRight.x), height: abs(topLeft.y - bottomRight.y))
    }
}
