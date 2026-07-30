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

    /// The fuel figure rendered beneath the balloon. A plain subview, so it does
    /// not participate in MapKit's marker collision logic — `collisionMode`
    /// interprets a frame derived from this view's own bounds, and the label is
    /// drawn outside them. Some overlap in an unusually dense block is accepted.
    let fuelLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.isHidden = true

        // Start from a preferred font so Dynamic Type applies, then add weight.
        let base = UIFont.preferredFont(forTextStyle: .caption1)
        let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) ?? base.fontDescriptor
        label.font = UIFont(descriptor: descriptor, size: 0)
        label.adjustsFontForContentSizeCategory = true

        // A white halo keeps the text legible over satellite basemaps.
        label.layer.shadowColor = UIColor.white.cgColor
        label.layer.shadowRadius = 2
        label.layer.shadowOpacity = 1
        label.layer.shadowOffset = .zero

        // The view composes its own accessibility label; a second element here
        // would make VoiceOver announce the figure twice.
        label.isAccessibilityElement = false

        return label
    }()

    public override var annotation: MKAnnotation? {
        didSet { configure() }
    }

    public override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = "rentals"
        // Rentals yield to transit stops when MapKit has to choose.
        displayPriority = .defaultLow
        titleVisibility = .hidden

        // The label sits outside bounds, so it must not be clipped.
        clipsToBounds = false
        addSubview(fuelLabel)
        NSLayoutConstraint.activate([
            fuelLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            // MKMarkerAnnotationView documents neither its bounds nor its default
            // centerOffset. Measured on iPhone 17 Pro / iOS 26.3: bounds
            // (0, 0, 31.33, 34.94), centerOffset (0, -17.47) — i.e.
            // centerOffset.y == -bounds.height/2, so MapKit places bounds.maxY at
            // the annotation's coordinate and the balloon tip sits there. Pinning
            // to bottomAnchor therefore tracks the tip even as the view's height
            // changes; the `1` below is a fixed gap, not a derived offset.
            fuelLabel.topAnchor.constraint(equalTo: bottomAnchor, constant: 1)
        ])

        configure()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        clusteringIdentifier = "rentals"
        displayPriority = .defaultLow
        // MKAnnotationView's default implementation does nothing, so subclass
        // state that isn't reset here leaks into the next annotation.
        fuelLabel.text = nil
        fuelLabel.isHidden = true
    }

    private func configure() {
        guard let rentalAnnotation = annotation as? RentalAnnotation else { return }
        let rental = rentalAnnotation.rental

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

        let fuelText = RentalFormat.fuelLabelText(for: rental)
        fuelLabel.text = fuelText
        fuelLabel.textColor = rental.isOperative ? .rentalPurple : .systemGray
        fuelLabel.isHidden = fuelText == nil || !rentalAnnotation.showsFuelLabel

        // VoiceOver ignores the zoom gate: a visual-density rule must not cost a
        // VoiceOver user information. The station occupancy line is carried across
        // explicitly because assigning accessibilityLabel replaces MapKit's
        // title/subtitle default — anything omitted here is silently lost.
        accessibilityLabel = [rental.displayLabel, rentalAnnotation.subtitle, fuelText]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    /// Applies just the zoom gate's decision, without re-running `configure()`.
    /// The gate flips on every crossing of the fuel-label zoom threshold, and a
    /// full reconfigure per visible annotation would re-resolve SF Symbols and
    /// re-run a distance formatter to change one Bool.
    func setShowsFuelLabel(_ shows: Bool) {
        fuelLabel.isHidden = !shows || fuelLabel.text == nil
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
