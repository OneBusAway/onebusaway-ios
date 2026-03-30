//
//  LiveActivityManager.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import ActivityKit
import Foundation
import MapKit
import OBAKitCore

/// Manages the lifecycle of transit arrival Live Activities.
@available(iOS 16.2, *)
public class LiveActivityManager {

    // MARK: - Duration Options

    public enum Duration: TimeInterval, CaseIterable {
        case fiveMinutes    = 300
        case fifteenMinutes = 900
        case thirtyMinutes  = 1800
        case oneHour        = 3600
        case twoHours       = 7200
        case fourHours      = 14400
        case eightHours     = 28800

        public var localizedTitle: String {
            switch self {
            case .fiveMinutes:    return OBALoc("live_activity.duration.5min",  value: "5 minutes",  comment: "Live Activity duration option")
            case .fifteenMinutes: return OBALoc("live_activity.duration.15min", value: "15 minutes", comment: "Live Activity duration option")
            case .thirtyMinutes:  return OBALoc("live_activity.duration.30min", value: "30 minutes", comment: "Live Activity duration option")
            case .oneHour:        return OBALoc("live_activity.duration.1hr",   value: "1 hour",     comment: "Live Activity duration option")
            case .twoHours:       return OBALoc("live_activity.duration.2hr",   value: "2 hours",    comment: "Live Activity duration option")
            case .fourHours:      return OBALoc("live_activity.duration.4hr",   value: "4 hours",    comment: "Live Activity duration option")
            case .eightHours:     return OBALoc("live_activity.duration.8hr",   value: "8 hours",    comment: "Live Activity duration option")
            }
        }
    }

    // MARK: - Properties

    private let userDefaults: UserDefaults
    private static let preferredDurationKey = "LiveActivityManager_preferredDuration"

    /// The last duration the user selected. Defaults to 1 hour.
    public var preferredDuration: Duration {
        get {
            let raw = userDefaults.double(forKey: Self.preferredDurationKey)
            return Duration(rawValue: raw) ?? .oneHour
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: Self.preferredDurationKey)
        }
    }

    /// Whether Live Activities are supported on this device/OS.
    public var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    // MARK: - Map Snapshot

    /// Generates a 144×144pt (@2x) Apple Maps snapshot centered on the given coordinate.
    /// Returns PNG data, or nil if snapshotting fails.
    private func mapSnapshot(latitude: Double, longitude: Double) async -> Data? {
        guard latitude != 0 || longitude != 0 else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            latitudinalMeters: 350,
            longitudinalMeters: 350
        )
        // 32×32px at scale 1 + JPEG 0.3 ≈ 1–2KB — safely under ActivityKit's 4KB payload limit.
        // The widget displays this at 72pt so it's a slight upscale, but map tiles look fine.
        options.size = CGSize(width: 32, height: 32)
        options.scale = 1
        options.mapType = .mutedStandard
        options.showsBuildings = false
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()

            let renderer = UIGraphicsImageRenderer(size: options.size)
            let image = renderer.image { _ in
                snapshot.image.draw(at: .zero)

                let pinSize: CGFloat = 8
                let center = snapshot.point(for: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                let pinRect = CGRect(
                    x: center.x - pinSize / 2,
                    y: center.y - pinSize / 2,
                    width: pinSize, height: pinSize
                )
                UIColor(red: 0.13, green: 0.84, blue: 0.46, alpha: 1).setFill()
                UIBezierPath(ovalIn: pinRect).fill()
                UIColor.white.setFill()
                UIBezierPath(ovalIn: pinRect.insetBy(dx: 2, dy: 2)).fill()
            }
            // JPEG at 0.3 quality — typically ~0.5–1KB for a 32×32 map tile, well under 4KB limit
            return image.jpegData(compressionQuality: 0.3)
        } catch {
            return nil
        }
    }

    // MARK: - Start

    /// Starts a Live Activity for the given bookmark and initial arrival departure.
    /// - Parameters:
    ///   - bookmark: The trip bookmark to track.
    ///   - arrivalDeparture: The initial arrival/departure data.
    ///   - duration: How long the activity should remain visible.
    @discardableResult
    public func startActivity(
        for bookmark: Bookmark,
        arrivalDeparture: ArrivalDeparture,
        duration: Duration
    ) async throws -> Activity<TransitArrivalAttributes>? {
        guard isSupported,
              let routeShortName = bookmark.routeShortName,
              let tripHeadsign = bookmark.tripHeadsign
        else { return nil }

        let attributes = TransitArrivalAttributes(
            stopName: bookmark.stop.name,
            routeShortName: routeShortName,
            tripHeadsign: tripHeadsign,
            stopID: bookmark.stopID,
            regionIdentifier: bookmark.regionIdentifier,
            stopLatitude: bookmark.stop.coordinate.latitude,
            stopLongitude: bookmark.stop.coordinate.longitude
        )

        // Start with no map image — payload must stay under ActivityKit's 4KB limit.
        // The map snapshot will be pushed on the first updateActivities call.
        let contentState = TransitArrivalAttributes.ContentState(
            arrivalDeparture: arrivalDeparture,
            mapImageData: nil
        )
        let staleDate = Date().addingTimeInterval(duration.rawValue)

        let content = ActivityContent(
            state: contentState,
            staleDate: staleDate,
            relevanceScore: 100
        )

        return try Activity<TransitArrivalAttributes>.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
    }

    // MARK: - Update

    /// Updates all active Live Activities matching the given stop/route/headsign with fresh arrival data.
    /// Map image is never re-sent in updates to stay under ActivityKit's 4KB payload limit.
    public func updateActivities(
        stopID: StopID,
        regionIdentifier: Int,
        routeShortName: String,
        tripHeadsign: String,
        arrivalDeparture: ArrivalDeparture
    ) async {
        for activity in Activity<TransitArrivalAttributes>.activities {
            guard activity.attributes.stopID == stopID,
                  activity.attributes.regionIdentifier == regionIdentifier,
                  activity.attributes.routeShortName == routeShortName,
                  activity.attributes.tripHeadsign == tripHeadsign
            else { continue }

            // Never include map image in updates — it pushes the payload over 4KB.
            // The map is shown from the last state that had it (or nil if never set).
            let newState = TransitArrivalAttributes.ContentState(
                arrivalDeparture: arrivalDeparture,
                mapImageData: activity.content.state.mapImageData
            )
            let content = ActivityContent(state: newState, staleDate: nil)
            await activity.update(content)
        }
    }

    /// Pushes the map snapshot to an activity after it has started.
    /// Called once after `startActivity` succeeds — separate from arrival updates.
    public func pushMapSnapshot(to activity: Activity<TransitArrivalAttributes>) async {
        let mapData = await mapSnapshot(
            latitude: activity.attributes.stopLatitude,
            longitude: activity.attributes.stopLongitude
        )
        guard let mapData else { return }

        let newState = TransitArrivalAttributes.ContentState(
            arrivalDepartureDate: activity.content.state.arrivalDepartureDate,
            minutesUntilArrival: activity.content.state.minutesUntilArrival,
            isPredicted: activity.content.state.isPredicted,
            scheduleStatus: activity.content.state.scheduleStatus,
            mapImageData: mapData
        )
        let content = ActivityContent(state: newState, staleDate: activity.content.staleDate)
        await activity.update(content)
    }

    // MARK: - Stop

    /// Ends all active Live Activities for the given stop/route/headsign.
    public func stopActivities(
        stopID: StopID,
        regionIdentifier: Int,
        routeShortName: String,
        tripHeadsign: String
    ) async {
        for activity in Activity<TransitArrivalAttributes>.activities {
            guard activity.attributes.stopID == stopID,
                  activity.attributes.regionIdentifier == regionIdentifier,
                  activity.attributes.routeShortName == routeShortName,
                  activity.attributes.tripHeadsign == tripHeadsign
            else { continue }

            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    // MARK: - Query

    /// Returns true if there is an active Live Activity for the given stop/route/headsign.
    public func hasActiveActivity(
        stopID: StopID,
        regionIdentifier: Int,
        routeShortName: String,
        tripHeadsign: String
    ) -> Bool {
        Activity<TransitArrivalAttributes>.activities.contains {
            $0.attributes.stopID == stopID &&
            $0.attributes.regionIdentifier == regionIdentifier &&
            $0.attributes.routeShortName == routeShortName &&
            $0.attributes.tripHeadsign == tripHeadsign &&
            $0.activityState == .active
        }
    }
}
