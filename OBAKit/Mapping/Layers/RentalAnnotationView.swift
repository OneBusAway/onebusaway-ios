//
//  RentalAnnotationView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OTPKit

extension UIColor {
    /// Rental purple (#7B4FD1) — matches OTPKit's trip-planner rental surfaces so
    /// rentals read as one system across the browse layer and planned routes.
    static let rentalPurple = UIColor(red: 0x7B / 255.0, green: 0x4F / 255.0, blue: 0xD1 / 255.0, alpha: 1.0)
}

/// Marker for a single rental entity. Free-floating vehicles (the dominant case)
/// get a form-factor glyph; docked stations get their availability count.
/// Non-operative entities render gray.
public class RentalAnnotationView: MKMarkerAnnotationView {

    public override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    public override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = "rentals"
        // Rentals yield to transit stops when MapKit has to choose.
        displayPriority = .defaultLow
        titleVisibility = .hidden
        configure()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        clusteringIdentifier = "rentals"
        displayPriority = .defaultLow
    }

    private func configure() {
        guard let rental = (annotation as? RentalAnnotation)?.rental else { return }

        markerTintColor = rental.isOperative ? .rentalPurple : .systemGray

        switch rental {
        case .station(let station):
            glyphImage = nil
            if let available = station.vehiclesAvailableCount {
                glyphText = String(available)
            } else {
                glyphText = nil
                glyphImage = UIImage(systemName: "bicycle")
            }
        case .vehicle(let vehicle):
            glyphText = nil
            glyphImage = UIImage(systemName: Self.glyphName(for: vehicle.vehicleType?.formFactor))
        }
    }

    private static func glyphName(for formFactor: VehicleFormFactor?) -> String {
        guard let formFactor else { return "bicycle" }
        if formFactor.isScooter { return "scooter" }
        if formFactor.isBicycle { return "bicycle" }
        switch formFactor {
        case .car: return "car"
        case .moped: return "moped"
        default: return "bicycle"
        }
    }
}

/// The cluster marker for piled-up rentals: a count badge in rental purple.
/// Registered per-annotation-type via the `viewFor` cluster arm — never via
/// `MKMapViewDefaultClusterAnnotationViewReuseIdentifier`, which would claim
/// cluster rendering for every annotation type on the map.
public class RentalClusterAnnotationView: MKMarkerAnnotationView {

    public override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    public override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        // A cluster represents many entities; it outranks individual markers.
        displayPriority = .defaultHigh
        titleVisibility = .hidden
        configure()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        guard let cluster = annotation as? MKClusterAnnotation else { return }
        markerTintColor = .rentalPurple
        glyphText = String(cluster.memberAnnotations.count)
    }
}
