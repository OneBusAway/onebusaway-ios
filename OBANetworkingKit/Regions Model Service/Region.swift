//
//  Region.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation
import MapKit

@objc(OBARegion)
public class Region: NSObject, Codable {
    public let regionName: String
    public let regionIdentifier: Int

    public let isActive: Bool
    public let isExperimental: Bool

    public let OBABaseURL: URL
    public let siriBaseURL: URL?
    public let openTripPlannerURL: URL?
    public let stopInfoURL: URL?

    public let regionBounds: [RegionBound]

    public let open311Servers: [Open311Server]

    public let supportsEmbeddedSocial: Bool
    public let supportsOBARealtimeAPIs: Bool
    public let supportsOBADiscoveryAPIs: Bool
    public let supportsOTPBikeshare: Bool
    public let supportsSiriRealtimeAPIs: Bool

    public let contactEmail: String
    public let twitterURL: URL?
    public let facebookURL: URL?
    public let openTripPlannerContactEmail: String?

    public let language: String?

    public let versionInfo: String

    public let paymentWarningBody: String?
    public let paymentWarningTitle: String?

    public let paymentAndroidAppID: String?
    public let paymentiOSAppStoreIdentifier: String?
    public let paymentiOSAppURLScheme: String?

    private enum CodingKeys: String, CodingKey {
        case regionName
        case regionIdentifier = "id"
        case isActive = "active"
        case isExperimental = "experimental"
        case OBABaseURL = "obaBaseUrl"
        case siriBaseURL = "siriBaseUrl"
        case openTripPlannerURL = "otpBaseUrl"
        case stopInfoURL = "stopInfoUrl"
        case regionBounds = "bounds"
        case open311Servers
        case supportsEmbeddedSocial
        case supportsOBARealtimeAPIs = "supportsObaRealtimeApis"
        case supportsOBADiscoveryAPIs = "supportsObaDiscoveryApis"
        case supportsOTPBikeshare = "supportsOtpBikeshare"
        case supportsSiriRealtimeAPIs = "supportsSiriRealtimeApis"
        case contactEmail
        case twitterURL = "twitterUrl"
        case facebookURL = "facebookUrl"
        case openTripPlannerContactEmail = "otpContactEmail"
        case language
        case versionInfo = "obaVersionInfo"
        case paymentWarningBody
        case paymentWarningTitle
        case paymentAndroidAppID = "paymentAndroidAppId"
        case paymentiOSAppStoreIdentifier = "paymentiOSAppStoreIdentifier"
        case paymentiOSAppURLScheme = "paymentiOSAppUrlScheme"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        regionName = try container.decode(String.self, forKey: .regionName)
        regionIdentifier = try container.decode(Int.self, forKey: .regionIdentifier)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        isExperimental = try container.decode(Bool.self, forKey: .isExperimental)

        OBABaseURL = try container.decode(URL.self, forKey: .OBABaseURL)
        siriBaseURL = try? container.decode(URL.self, forKey: .siriBaseURL)
        openTripPlannerURL = try? container.decode(URL.self, forKey: .openTripPlannerURL)
        stopInfoURL = try? container.decode(URL.self, forKey: .stopInfoURL)

        regionBounds = try container.decode([RegionBound].self, forKey: .regionBounds)

        open311Servers = try container.decode([Open311Server].self, forKey: .open311Servers)

        supportsEmbeddedSocial = try container.decode(Bool.self, forKey: .supportsEmbeddedSocial)
        supportsOBARealtimeAPIs = try container.decode(Bool.self, forKey: .supportsOBARealtimeAPIs)
        supportsOBADiscoveryAPIs = try container.decode(Bool.self, forKey: .supportsOBADiscoveryAPIs)
        supportsOTPBikeshare = try container.decode(Bool.self, forKey: .supportsOTPBikeshare)
        supportsSiriRealtimeAPIs = try container.decode(Bool.self, forKey: .supportsSiriRealtimeAPIs)

        contactEmail = try container.decode(String.self, forKey: .contactEmail)

        twitterURL = try? container.decode(URL.self, forKey: .twitterURL)
        facebookURL = try? container.decode(URL.self, forKey: .facebookURL)
        openTripPlannerContactEmail = try? container.decode(String.self, forKey: .openTripPlannerContactEmail)

        language = try container.decode(String.self, forKey: .language)
        versionInfo = try container.decode(String.self, forKey: .versionInfo)

        paymentWarningBody = try? container.decode(String.self, forKey: .paymentWarningBody)
        paymentWarningTitle = try? container.decode(String.self, forKey: .paymentWarningTitle)

        paymentAndroidAppID = try? container.decode(String.self, forKey: .paymentAndroidAppID)
        paymentiOSAppStoreIdentifier = try? container.decode(String.self, forKey: .paymentiOSAppStoreIdentifier)
        paymentiOSAppURLScheme = try? container.decode(String.self, forKey: .paymentiOSAppURLScheme)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(regionName, forKey: .regionName)
        try container.encode(regionIdentifier, forKey: .regionIdentifier)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(isExperimental, forKey: .isExperimental)
        try container.encode(OBABaseURL, forKey: .OBABaseURL)
        try? container.encode(siriBaseURL, forKey: .siriBaseURL)
        try? container.encode(openTripPlannerURL, forKey: .openTripPlannerURL)
        try? container.encode(stopInfoURL, forKey: .stopInfoURL)
        try container.encode(regionBounds, forKey: .regionBounds)
        try container.encode(open311Servers, forKey: .open311Servers)
        try container.encode(supportsEmbeddedSocial, forKey: .supportsEmbeddedSocial)
        try container.encode(supportsOBARealtimeAPIs, forKey: .supportsOBARealtimeAPIs)
        try container.encode(supportsOBADiscoveryAPIs, forKey: .supportsOBADiscoveryAPIs)
        try container.encode(supportsOTPBikeshare, forKey: .supportsOTPBikeshare)
        try container.encode(supportsSiriRealtimeAPIs, forKey: .supportsSiriRealtimeAPIs)
        try container.encode(contactEmail, forKey: .contactEmail)
        try? container.encode(twitterURL, forKey: .twitterURL)
        try? container.encode(facebookURL, forKey: .facebookURL)
        try? container.encode(openTripPlannerContactEmail, forKey: .openTripPlannerContactEmail)
        try container.encode(language, forKey: .language)
        try container.encode(versionInfo, forKey: .versionInfo)
        try? container.encode(paymentWarningBody, forKey: .paymentWarningBody)
        try? container.encode(paymentWarningTitle, forKey: .paymentWarningTitle)
        try? container.encode(paymentAndroidAppID, forKey: .paymentAndroidAppID)
        try? container.encode(paymentiOSAppStoreIdentifier, forKey: .paymentiOSAppStoreIdentifier)
        try? container.encode(paymentiOSAppURLScheme, forKey: .paymentiOSAppURLScheme)
    }

    // MARK: - NSObject Overrides

    public override var debugDescription: String {
        return "\(super.debugDescription) - \(regionName)"
    }

    // MARK: - Regional Boundaries

    @objc public lazy var serviceRect: MKMapRect = {
        var minX: Double = .greatestFiniteMagnitude
        var minY: Double = .greatestFiniteMagnitude
        var maxX: Double = .leastNormalMagnitude
        var maxY: Double = .leastNormalMagnitude

        for bounds in regionBounds {
            let a = MKMapPoint(CLLocationCoordinate2D(latitude: bounds.lat + bounds.latSpan / 2.0, longitude: bounds.lon - bounds.lonSpan / 2.0))
            let b = MKMapPoint(CLLocationCoordinate2D(latitude: bounds.lat - bounds.latSpan / 2.0, longitude: bounds.lon + bounds.lonSpan / 2.0))

            minX = min(minX, min(a.x, b.x))
            minY = min(minY, min(a.y, b.y))
            maxX = max(maxX, max(a.x, b.x))
            maxY = max(maxY, max(a.y, b.y))
        }

        return MKMapRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }()

    public lazy var centerCoordinate: CLLocationCoordinate2D = {
        let rect = serviceRect
        let centerPoint = MKMapPoint(x: rect.midX, y: rect.midY)

        return centerPoint.coordinate
    }()

    public func distanceFrom(location: CLLocation) -> CLLocationDistance {
        let centerLocation = CLLocation(latitude: centerCoordinate.latitude, longitude: centerCoordinate.longitude)
        return location.distance(from: centerLocation)
    }

    @objc public func contains(location: CLLocation?) -> Bool {
        guard let location = location else {
            return false
        }

        let point = MKMapPoint(location.coordinate)
        return serviceRect.contains(point)
    }
}

// MARK: - Open311Server
public class Open311Server: NSObject, Codable {
    public let jurisdictionID: String?
    public let apiKey: String
    public let baseURL: URL

    private enum CodingKeys: String, CodingKey {
        case jurisdictionID = "jurisdictionId"
        case apiKey
        case baseURL = "baseUrl"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jurisdictionID = try? container.decode(String.self, forKey: .jurisdictionID)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        baseURL = try container.decode(URL.self, forKey: .baseURL)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try? container.encode(jurisdictionID, forKey: .jurisdictionID)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(baseURL, forKey: .baseURL)
    }
}

// MARK: - RegionBound
public class RegionBound: NSObject, Codable {
    let lat: Double
    let lon: Double
    let latSpan: Double
    let lonSpan: Double

    private enum CodingKeys: String, CodingKey {
        case lat, lon, latSpan, lonSpan
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lat = try container.decode(Double.self, forKey: .lat)
        lon = try container.decode(Double.self, forKey: .lon)
        latSpan = try container.decode(Double.self, forKey: .latSpan)
        lonSpan = try container.decode(Double.self, forKey: .lonSpan)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lat, forKey: .lat)
        try container.encode(lon, forKey: .lon)
        try container.encode(latSpan, forKey: .latSpan)
        try container.encode(lonSpan, forKey: .lonSpan)
    }
}
