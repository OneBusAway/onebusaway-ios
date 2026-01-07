//
//  UserPinAnnotationView.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 1/6/26.
//

import MapKit

/// A custom annotation view for user-dropped pins on the map.
///
/// This view extends `MKMarkerAnnotationView` to add tap gesture recognition,
/// allowing the app to respond when users tap on pins they've placed on the map.
final class UserPinAnnotationView: MKMarkerAnnotationView {
    /// A closure that is called when the user taps on this annotation view.
    ///
    /// Set this property to handle tap interactions on the pin. The closure is
    /// automatically cleared in `prepareForReuse()` to prevent stale references
    /// when the view is recycled.
    var onTap: (() -> Void)?

    /// Creates a new user pin annotation view with the specified annotation and reuse identifier.
    ///
    /// - Parameters:
    ///   - annotation: The annotation object to associate with this view.
    ///   - reuseIdentifier: A string used to identify this view for reuse.
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupGestures()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGestures()
    }

    private func setupGestures() {
        isUserInteractionEnabled = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.onTap = nil
    }

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
        guard gr.state == .ended else { return }
        onTap?()
    }
}
