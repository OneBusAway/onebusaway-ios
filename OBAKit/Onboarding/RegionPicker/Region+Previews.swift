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

/// A region provider for Xcode Previews.
final class Previews_SampleRegionProvider: RegionProvider {
    @Published var allRegions: [Region] = [
        .regionForPreview(id: 0, name: "Tampa Bay", latitude: 27.9769105, longitude: -82.445851, latitudeSpan: 0.5424609, longitudeSpan: 0.5763579),
        .regionForPreview(id: 1, name: "Puget Sound", latitude: 47.59820, longitude: -122.32165, latitudeSpan: 0.33704, longitudeSpan: 0.440483),
        .regionForPreview(id: 2, name: "MTA New York", latitude: 40.707678, longitude: -74.017681, latitudeSpan: 0.40939, longitudeSpan: 0.468666),
        .regionForPreview(id: 3, name: "Atlanta", latitude: 33.74819, longitude: -84.39086, latitudeSpan: 0.066268, longitudeSpan: 0.051677),
        .regionForPreview(id: 15, name: "Adelaide Metro", latitude: -34.833098, longitude: 138.621111, latitudeSpan: 0.52411, longitudeSpan: 0.285071)
    ]

    @Published fileprivate(set) var currentRegion: Region?
    @Published var automaticallySelectRegion: Bool = false {
        didSet {
            if automaticallySelectRegion {
                currentRegion = allRegions[3]
            }
        }
    }

    init() {
        self.currentRegion = allRegions[2]
    }

    func refreshRegions() async throws {
        try await Task.sleep(nanoseconds: 1_000_000_000)

        throw NSError(domain: "org.onebusaway.iphone", code: 418, userInfo: [
            NSLocalizedDescriptionKey: "\(#function) error!"
        ])
    }

    func setCurrentRegion(to newRegion: Region) async throws {
        try await Task.sleep(nanoseconds: 1_000_000_000)

        throw NSError(domain: "org.onebusaway.iphone", code: 418, userInfo: [
            NSLocalizedDescriptionKey: "\(#function) error!"
        ])
    }

    func add(customRegion newRegion: OBAKitCore.Region) async throws {
        try await Task.sleep(nanoseconds: 1_000_000_000)

        throw NSError(domain: "org.onebusaway.iphone", code: 418, userInfo: [
            NSLocalizedDescriptionKey: "\(#function) error!"
        ])
    }

    func delete(customRegion region: Region) async throws {
        try await Task.sleep(nanoseconds: 1_000_000_000)

        guard let index = allRegions.firstIndex(of: region) else {
            return
        }

        allRegions.remove(at: index)
    }
}

#endif
