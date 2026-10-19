//
//  ReportedPositionAnnotation.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore
import UIKit

/// Debug: where the feed put an estimated vehicle, drawn beside its marker so the
/// estimate can be compared with what it replaced. See `FeatureFlags.showsRawVehicleFixKey`.
enum ReportedPositionKind: Equatable {
    /// `TripStatus.lastKnownLocation`, the raw GPS fix the estimate starts from.
    case lastKnownLocation
    /// `TripStatus.position`: on Java servers the schedule's location at the fix
    /// time, on maglev the fix snapped to the shape.
    case serverPosition

    /// Both, for a vehicle being estimated, in a fixed order.
    static func positions(of status: TripStatus?) -> [(kind: ReportedPositionKind, coordinate: CLLocationCoordinate2D)] {
        guard let status else { return [] }
        return [
            status.lastKnownLocation.map { (ReportedPositionKind.lastKnownLocation, $0.coordinate) },
            status.position.map { (ReportedPositionKind.serverPosition, $0.coordinate) }
        ]
        .compactMap { $0 }
        .filter { !$0.1.isNullIsland }
    }

    var color: UIColor {
        switch self {
        case .lastKnownLocation: .label
        case .serverPosition: .systemPurple
        }
    }
}

final class ReportedPositionAnnotation: MKPointAnnotation {
    let kind: ReportedPositionKind

    init(kind: ReportedPositionKind, coordinate: CLLocationCoordinate2D) {
        self.kind = kind
        super.init()
        self.coordinate = coordinate
    }

    // Matches the isolation of the nonisolated MKPointAnnotation initializer; see `VehicleAnnotation`.
    nonisolated override init() {
        fatalError("Use init(kind:coordinate:).")
    }
}

/// A small hollow ring, in the kind's color.
final class ReportedPositionAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "ReportedPositionAnnotationView"
    static let diameter: CGFloat = 14

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter)
        layer.cornerRadius = Self.diameter / 2
        layer.borderWidth = 2.5
        isUserInteractionEnabled = false
        // Debug-only, and undrawn without a hidden toggle: not worth a rotor stop.
        isAccessibilityElement = false
        displayPriority = .required
        zPriority = .max
        applyKind()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var annotation: MKAnnotation? {
        didSet { applyKind() }
    }

    private func applyKind() {
        layer.borderColor = (annotation as? ReportedPositionAnnotation)?.kind.color.cgColor
    }
}
