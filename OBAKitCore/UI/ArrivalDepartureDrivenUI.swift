//
//  ArrivalDepartureDrivenUI.swift
//  OBAKit
//
//  Created by Alan Chu on 6/2/20.
//

#if !os(watchOS)
import UIKit

/// Tracks arrival/departure times for `ArrivalDeparture`s.
public typealias ArrivalDepartureTimes = [TripIdentifier: Int]

/// - `cellForItem` use `configure(with:_)`.
/// - `willDisplayCell` use `highlightIfNeeded(:_)`.
public protocol ArrivalDepartureDrivenUI: UIView {
    /// The color that is used to highlight a value change in this label. Used by `highlightBackground()`.
    var highlightedBackgroundColor: UIColor { get set }

    /// Configures the view with the provided parameters.
    /// - parameter arrivalDeparture: The `ArrivalDeparture` object to configure the view with.
    /// - parameter formatters: Formatters necessary for localizing data.
    func configure(with arrivalDeparture: ArrivalDeparture, formatters: Formatters)

    /// Causes the background of the label to be highlighted for `Animations.longAnimationDuration`.
    func highlightBackground()

    /// This determines if there is a change in the `arrivalDeparture` time based on the provided
    /// `arrivalDepartureTimes` and performs the UI animations to highlight the update (calls `hightlightBackground()`).
    /// If the `arrivalDeparture` is not present in the provided `arrivalDepartureTimes`,
    ///  this will not highlight changes but will add it to `arrivalDepartureTimes` for future comparisons. (aka this method checks for updates among existing data, not additions)
    /// - parameter arrivalDeparture: The `ArrivalDeparture` object to compare against the times
    /// - parameter basedOn: The times to compare against.
    func highlightIfNeeded(arrivalDeparture: ArrivalDeparture, basedOn arrivalDepartureTimes: inout ArrivalDepartureTimes)
}

// MARK: - Default implementation
extension ArrivalDepartureDrivenUI {
    public func highlightIfNeeded(arrivalDeparture: ArrivalDeparture, basedOn arrivalDepartureTimes: inout ArrivalDepartureTimes) {
        if let lastMinutes = arrivalDepartureTimes[arrivalDeparture.tripID] {
            // If the arrival departure time is different, highlight background.
            if lastMinutes != arrivalDeparture.arrivalDepartureMinutes {
                self.highlightBackground()
            }
        }

        arrivalDepartureTimes[arrivalDeparture.tripID] = arrivalDeparture.arrivalDepartureMinutes
    }
}
#endif
