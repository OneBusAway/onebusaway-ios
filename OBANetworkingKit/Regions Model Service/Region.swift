//
//  Region.swift
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 11/10/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation

public class Region: NSObject, Decodable {
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
}

public class Open311Server: NSObject, Decodable {
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
}

public class RegionBound: NSObject, Decodable {
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
}
