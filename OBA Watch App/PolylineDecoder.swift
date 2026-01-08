import Foundation
import CoreLocation

enum PolylineDecoder {
    /// Decodes a Google-style encoded polyline string into an array of
    /// CLLocationCoordinate2D. Returns an empty array if decoding fails.
    static func decode(encodedPolyline: String) -> [CLLocationCoordinate2D] {
        let data = Array(encodedPolyline.utf8)
        var index = 0
        let length = data.count
        var latitude: Int32 = 0
        var longitude: Int32 = 0
        var coordinates: [CLLocationCoordinate2D] = []

        while index < length {
            var result: Int32 = 0
            var shift: Int32 = 0
            var byte: UInt8

            repeat {
                guard index < length else { return coordinates }
                byte = data[index] - 63
                index += 1
                result |= Int32(byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20

            let deltaLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            latitude += deltaLat

            result = 0
            shift = 0

            repeat {
                guard index < length else { return coordinates }
                byte = data[index] - 63
                index += 1
                result |= Int32(byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20

            let deltaLon = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            longitude += deltaLon

            let lat = Double(latitude) / 1e5
            let lon = Double(longitude) / 1e5
            coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        return coordinates
    }
}
