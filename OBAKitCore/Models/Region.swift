//
//  Region.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import MapKit

public typealias RegionIdentifier = Int

/// Represents a OneBusAway server deployment.
/// For example, OBA regions include Tampa, Puget Sound, and Washington, D.C.
public class Region: NSObject, Identifiable, Codable {

    /// The human-readable name of the region. Example: Puget Sound.
    public let name: String

    public var id: RegionIdentifier {
        return self.regionIdentifier
    }

    /// The unique ID for the region.
    public let regionIdentifier: RegionIdentifier

    /// Is this region functional?
    ///
    /// TRUE if this OBA instance is active (i.e., it will respond to requests), and FALSE if this OBA instance is inactive (i.e., it will not respond to requests)
    public let isActive: Bool

    /// Is this region publicly supported?
    ///
    /// `true` if the server is experimental and has not yet been approved by the community as a "production" OBA server.
    /// Mobile app users have to explicitly opt-in to see experimental servers in the app.
    /// `false` if the OBA community has approved this server as a "production" server that appears by default in the mobile apps.
    /// See https://groups.google.com/forum/#!topic/onebusaway-developers/xxkBT8GN_PY for details.
    public let isExperimental: Bool

    /// Custom regions are created by the user inside of the app for testing purposes. These are not regions that exist within the `regions` JSON file.
    public let isCustom: Bool?

    /// The base URL for making OBA REST API requests.
    public let OBABaseURL: URL

    /// The base URL for sidecar server (i.e. OneBusAway.co/Obaco) REST API requests
    public let sidecarBaseURL: URL?

    /// The base URL for reporting analytics to a Plausible Analytics server
    public let plausibleAnalyticsServerURL: URL?

    /// The base URL for making Service Interface for Real Time Information (SIRI) requests.
    ///
    /// true if this OBA instance supports using the SIRI Real-time APIs to find out real-time
    /// information about the transit system (e.g., how long until my bus arrives?),
    /// false if it does not. If the value is true, the field `SIRIBaseURL` must be populated.
    /// If the value is false, the field `SIRIBaseURL` should not be populated.
    /// See https://en.wikipedia.org/wiki/Service_Interface_for_Real_Time_Information for more information.
    public let siriBaseURL: URL?

    /// The base URL for making OpenTripPlanner (OTP) requests.
    public let openTripPlannerURL: URL?

    /// The base URL of a stop info server (used for crowd-sourcing bus stop info for blind or low-vision riders) for the given region
    /// If no stop info server is available, this field will be blank.
    /// See https://groups.google.com/forum/#!topic/onebusaway-developers/zE-8IqmY1a4 for details.
    public let stopInfoURL: URL?

    /// A list of Open 311 servers for this region.
    public let open311Servers: [Open311Server]?

    /// Does this region support Microsoft Research's Embedded Social SDK?
    ///
    /// TRUE if the Microsoft Embedded Social features should be shown for this region, and FALSE if the Embedded Social features should not be shown.  Valid values are only TRUE or FALSE.
    public let supportsEmbeddedSocial: Bool

    /// Does this region support OBA Realtime APIs?
    ///
    /// true if this OBA instance supports using the OBA Real-time APIs to find out real-time information
    /// about the transit system (e.g., how long until my bus arrives?), false if it does not.
    /// Valid values are only true or false. If the value is true, the field `OBABaseURL` must be populated.
    public let supportsOBARealtimeAPIs: Bool

    /// Does this region support using the OBA Discovery APIs to find out static information about the transit system?
    ///
    /// For example: what route IDs are available for an agency?
    /// If the value is true, then the field `OBABaseURL` must be populated.
    public let supportsOBADiscoveryAPIs: Bool

    public let supportsOTPBikeshare: Bool

    /// Does this OBA instance supports using the SIRI Real-time APIs to find out real-time information about the transit system?
    ///
    /// (e.g., how long until my bus arrives?), FALSE if it does not.  Valid values are only TRUE or FALSE.   If the value is TRUE, the field "SIRI Base URL" must be populated.  If the value is False, the field "SIRI Base URL" should NOT be populated.
    public let supportsSiriRealtimeAPIs: Bool

    /// The region's contact person's email.
    ///
    /// Mobile app users can send an email inside the OBA app to the maintainer of the OBA server
    /// they are using in order to report an issue or send feedback.
    public let contactEmail: String

    /// The URL of the Twitter feed for the region (e.g., http://mobile.twitter.com/onebusaway)
    ///
    /// This URL will be accessible to users in the "Contact Us" portion of the apps, where
    /// they will be directed to this Twitter page in a web browser or mobile Twitter app.
    public let twitterURL: URL?

    /// The 'long format' URL of the Facebook page for the region
    ///
    /// e.g., https://www.facebook.com/pages/ObaAtlanta/136662306506627
    /// This URL will be accessible to users in the "Contact Us" portion of the apps,
    /// where they will be directed to this Facebook page in a web browser or mobile Facebook app.
    public let facebookURL: URL?

    /// The contact email address for customer support for the OpenTripPlanner server for this region
    ///
    /// The OBA apps will direct user feedback to this email address if there are problems with a
    /// planned trip (e.g., cannot plan a trip between a specific origin and destination).
    /// If OTP_Base_URL contains a value, OTP_Contact_Email should also contain a value.
    public let openTripPlannerContactEmail: String?

    /// The locale of the OBA server.
    ///
    /// It consists of a two-letter lowercase ISO language codes (such as "en")
    /// as defined by ISO 639-1, then an underscore, and then a two-letter uppercase
    /// ISO country codes (such as "US") as defined by ISO 3166-1.
    public let language: String?

    /// This is the current version of your OBA server.
    ///
    /// This should be defined in the format <version|major|minor|incremental|qualifier|commit>, where the version|major|minor|incremental|qualifier are the version numbers of the OBA server (from your onebusaway-application-modules pom.xml), and commit is the Git SHA-1 hash from the most recent commit for the OBA onebusaway-application-modules code deployed to the server.
    ///
    /// For example, 1.1.8-SNAPSHOT|1|1|8|SNAPSHOT|877d870ac5c5f64607113d08d6d362925839719e
    public let versionInfo: String

    /// The body text of a warning dialog that should be shown to the user the first time
    /// they select the fare payment option, or empty if no warning should be shown to the user.
    /// If this field is populated, then Payment_Warning_Title must also be populated.
    /// If this field is empty, then Payment_Warning_Title must also be empty.
    public let paymentWarningBody: String?

    /// The title of a warning dialog that should be shown to the user the first time
    /// they select the fare payment option, or empty if no warning should be shown to the user.
    /// If this field is populated, then Payment_Warning_Body must also be populated.
    /// If this field is empty, then Payment_Warning_Body must also be empty.
    public let paymentWarningTitle: String?

    /// The application ID (i.e., the Google Play listing ID) for the Android app used for mobile fare payment for the region
    public let paymentAndroidAppID: String?

    /// The application ID (i.e., the Apple App Store listing ID) for the iOS app used for mobile fare payment for the region.
    public let paymentiOSAppStoreIdentifier: String?

    /// The URL scheme that can be used on iOS to launch the mobile fare payment app for the region.
    ///
    /// More information on this iOS feature can be found here: https://developer.apple.com/documentation/uikit/core_app/allowing_apps_and_websites_to_link_to_your_content/communicating_with_other_apps_using_custom_urls?language=objc
    public let paymentiOSAppURLScheme: String?

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case name = "regionName"
        case regionIdentifier = "id"
        case isActive = "active"
        case isCustom = "custom"
        case isExperimental = "experimental"
        case sidecarBaseURL = "sidecarBaseUrl"
        case plausibleAnalyticsServerURL = "plausibleAnalyticsServerUrl"
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

    /// Allows you to create custom `Region` objects within the app.
    ///
    /// This is useful for testing out new regions.
    /// - Parameter name: The user-visible name of the region.
    /// - Parameter OBABaseURL: The base URL against which API requests will be made.
    /// - Parameter coordinateRegion: The coordinate region that circumscribes this region.
    /// - Parameter contactEmail: The contact email address for this region.
    /// - Parameter regionIdentifier: The identifier for this region. If unassigned, it will be given a random value.
    /// - Parameter regionIdentifier: The identifier for this region. If unassigned, it will be given a random value.
    public required init(name: String, OBABaseURL: URL, coordinateRegion: MKCoordinateRegion, contactEmail: String, regionIdentifier: Int? = nil, openTripPlannerURL: URL? = nil) {
        self.name = name
        self.regionIdentifier = regionIdentifier ?? 1000 + Int.random(in: 0...999)
        isActive = true
        isExperimental = false
        isCustom = true

        self.OBABaseURL = OBABaseURL
        self.sidecarBaseURL = nil

        let bound = RegionBound(lat: coordinateRegion.center.latitude, lon: coordinateRegion.center.longitude, latSpan: coordinateRegion.span.latitudeDelta, lonSpan: coordinateRegion.span.longitudeDelta)
        regionBounds = [bound]
        self.contactEmail = contactEmail

        self.openTripPlannerURL = openTripPlannerURL

        // Uninitialized properties
        facebookURL = nil
        language = "en_US"
        open311Servers = []
        openTripPlannerContactEmail = nil

        paymentAndroidAppID = nil
        paymentWarningBody = nil
        paymentWarningTitle = nil
        paymentiOSAppStoreIdentifier = nil
        paymentiOSAppURLScheme = nil
        plausibleAnalyticsServerURL = nil
        siriBaseURL = nil
        stopInfoURL = nil
        supportsEmbeddedSocial = false
        supportsOBADiscoveryAPIs = true
        supportsOBARealtimeAPIs = true
        supportsOTPBikeshare = false
        supportsSiriRealtimeAPIs = false
        twitterURL = nil
        versionInfo = "x.y.z.custom"
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        name = try container.decode(String.self, forKey: .name)
        regionIdentifier = try container.decode(Int.self, forKey: .regionIdentifier)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        isExperimental = try container.decode(Bool.self, forKey: .isExperimental)
        isCustom = (try? container.decodeIfPresent(Bool.self, forKey: .isCustom)) ?? false

        OBABaseURL = try container.decode(URL.self, forKey: .OBABaseURL)
        sidecarBaseURL = try? container.decodeIfPresent(URL.self, forKey: .sidecarBaseURL)
        siriBaseURL = try? container.decodeIfPresent(URL.self, forKey: .siriBaseURL)
        openTripPlannerURL = try? container.decodeIfPresent(URL.self, forKey: .openTripPlannerURL)
        stopInfoURL = try? container.decodeIfPresent(URL.self, forKey: .stopInfoURL)
        plausibleAnalyticsServerURL = try? container.decodeIfPresent(URL.self, forKey: .plausibleAnalyticsServerURL)

        regionBounds = try container.decode([RegionBound].self, forKey: .regionBounds)

        open311Servers = try container.decodeIfPresent([Open311Server].self, forKey: .open311Servers)

        supportsEmbeddedSocial = try container.decode(Bool.self, forKey: .supportsEmbeddedSocial)
        supportsOBARealtimeAPIs = try container.decode(Bool.self, forKey: .supportsOBARealtimeAPIs)
        supportsOBADiscoveryAPIs = try container.decode(Bool.self, forKey: .supportsOBADiscoveryAPIs)
        supportsOTPBikeshare = try (container.decodeIfPresent(Bool.self, forKey: .supportsOTPBikeshare) ?? false)
        supportsSiriRealtimeAPIs = try container.decode(Bool.self, forKey: .supportsSiriRealtimeAPIs)

        contactEmail = try container.decode(String.self, forKey: .contactEmail)

        twitterURL = try? container.decodeGarbageURL(forKey: .twitterURL)
        facebookURL = try? container.decodeGarbageURL(forKey: .facebookURL)
        openTripPlannerContactEmail = try? container.decodeIfPresent(String.self, forKey: .openTripPlannerContactEmail)

        language = try container.decode(String.self, forKey: .language)
        versionInfo = try container.decode(String.self, forKey: .versionInfo)

        paymentWarningBody = try? container.decodeIfPresent(String.self, forKey: .paymentWarningBody)
        paymentWarningTitle = try? container.decodeIfPresent(String.self, forKey: .paymentWarningTitle)

        paymentAndroidAppID = try? container.decodeIfPresent(String.self, forKey: .paymentAndroidAppID)
        paymentiOSAppStoreIdentifier = try? container.decodeIfPresent(String.self, forKey: .paymentiOSAppStoreIdentifier)
        paymentiOSAppURLScheme = try? container.decodeIfPresent(String.self, forKey: .paymentiOSAppURLScheme)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(regionIdentifier, forKey: .regionIdentifier)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(isExperimental, forKey: .isExperimental)
        try container.encode(isCustom, forKey: .isCustom)
        try container.encode(OBABaseURL, forKey: .OBABaseURL)
        try container.encode(sidecarBaseURL, forKey: .sidecarBaseURL)
        try container.encode(plausibleAnalyticsServerURL, forKey: .plausibleAnalyticsServerURL)
        try container.encodeIfPresent(siriBaseURL, forKey: .siriBaseURL)
        try container.encodeIfPresent(openTripPlannerURL, forKey: .openTripPlannerURL)
        try container.encodeIfPresent(stopInfoURL, forKey: .stopInfoURL)
        try container.encode(regionBounds, forKey: .regionBounds)
        try container.encodeIfPresent(open311Servers, forKey: .open311Servers)
        try container.encode(supportsEmbeddedSocial, forKey: .supportsEmbeddedSocial)
        try container.encode(supportsOBARealtimeAPIs, forKey: .supportsOBARealtimeAPIs)
        try container.encode(supportsOBADiscoveryAPIs, forKey: .supportsOBADiscoveryAPIs)
        try container.encode(supportsOTPBikeshare, forKey: .supportsOTPBikeshare)
        try container.encode(supportsSiriRealtimeAPIs, forKey: .supportsSiriRealtimeAPIs)
        try container.encode(contactEmail, forKey: .contactEmail)
        try container.encodeIfPresent(twitterURL?.absoluteString, forKey: .twitterURL)
        try container.encodeIfPresent(facebookURL?.absoluteString, forKey: .facebookURL)
        try container.encodeIfPresent(openTripPlannerContactEmail, forKey: .openTripPlannerContactEmail)
        try container.encode(language, forKey: .language)
        try container.encode(versionInfo, forKey: .versionInfo)
        try container.encodeIfPresent(paymentWarningBody, forKey: .paymentWarningBody)
        try container.encodeIfPresent(paymentWarningTitle, forKey: .paymentWarningTitle)
        try container.encodeIfPresent(paymentAndroidAppID, forKey: .paymentAndroidAppID)
        try container.encodeIfPresent(paymentiOSAppStoreIdentifier, forKey: .paymentiOSAppStoreIdentifier)
        try container.encodeIfPresent(paymentiOSAppURLScheme, forKey: .paymentiOSAppURLScheme)
    }

    // MARK: - NSObject Overrides

    public override var debugDescription: String {
        return "\(super.debugDescription) - \(name)"
    }

    // MARK: - Equality and Hashing

    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? Region else { return false }
        return name == rhs.name &&
            regionIdentifier == rhs.regionIdentifier &&
            isActive == rhs.isActive &&
            isExperimental == rhs.isExperimental &&
            isCustom == rhs.isCustom &&
            OBABaseURL == rhs.OBABaseURL &&
            sidecarBaseURL == rhs.sidecarBaseURL &&
            siriBaseURL == rhs.siriBaseURL &&
            openTripPlannerURL == rhs.openTripPlannerURL &&
            plausibleAnalyticsServerURL == rhs.plausibleAnalyticsServerURL &&
            stopInfoURL == rhs.stopInfoURL &&
            open311Servers == rhs.open311Servers &&
            supportsEmbeddedSocial == rhs.supportsEmbeddedSocial &&
            supportsOBARealtimeAPIs == rhs.supportsOBARealtimeAPIs &&
            supportsOBADiscoveryAPIs == rhs.supportsOBADiscoveryAPIs &&
            supportsOTPBikeshare == rhs.supportsOTPBikeshare &&
            supportsSiriRealtimeAPIs == rhs.supportsSiriRealtimeAPIs &&
            contactEmail == rhs.contactEmail &&
            twitterURL == rhs.twitterURL &&
            facebookURL == rhs.facebookURL &&
            openTripPlannerContactEmail == rhs.openTripPlannerContactEmail &&
            language == rhs.language &&
            versionInfo == rhs.versionInfo &&
            paymentWarningBody == rhs.paymentWarningBody &&
            paymentWarningTitle == rhs.paymentWarningTitle &&
            paymentAndroidAppID == rhs.paymentAndroidAppID &&
            paymentiOSAppStoreIdentifier == rhs.paymentiOSAppStoreIdentifier &&
            paymentiOSAppURLScheme == rhs.paymentiOSAppURLScheme
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(name)
        hasher.combine(regionIdentifier)
        hasher.combine(isActive)
        hasher.combine(isExperimental)
        hasher.combine(isCustom)
        hasher.combine(OBABaseURL)
        hasher.combine(sidecarBaseURL)
        hasher.combine(siriBaseURL)
        hasher.combine(plausibleAnalyticsServerURL)
        hasher.combine(openTripPlannerURL)
        hasher.combine(stopInfoURL)
        hasher.combine(open311Servers)
        hasher.combine(supportsEmbeddedSocial)
        hasher.combine(supportsOBARealtimeAPIs)
        hasher.combine(supportsOBADiscoveryAPIs)
        hasher.combine(supportsOTPBikeshare)
        hasher.combine(supportsSiriRealtimeAPIs)
        hasher.combine(contactEmail)
        hasher.combine(twitterURL)
        hasher.combine(facebookURL)
        hasher.combine(openTripPlannerContactEmail)
        hasher.combine(language)
        hasher.combine(versionInfo)
        hasher.combine(paymentWarningBody)
        hasher.combine(paymentWarningTitle)
        hasher.combine(paymentAndroidAppID)
        hasher.combine(paymentiOSAppStoreIdentifier)
        hasher.combine(paymentiOSAppURLScheme)
        return hasher.finalize()
    }

    // MARK: - Location Helpers

    /// Internal type for constructing regional boundaries from the server's JSON output.
    struct RegionBound: Codable {
        let lat: Double
        let lon: Double
        let latSpan: Double
        let lonSpan: Double

        /// The center coordinate of this `RegionBound`
        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        var latSpanMeters: CLLocationDistance {
            111320.0 * latSpan
        }

        var lonSpanMeters: CLLocationDistance {
            40075000.0 * cos(lat) / 360.0
        }
    }

    /// An internal array of region boundaries. Use `serviceRect` instead.
    let regionBounds: [RegionBound]

    /// Returns a map rect that describes this region's boundaries.
    public lazy var serviceRect: MKMapRect = {
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

    /// Returns the center coordinate of `serviceRect`.
    public lazy var centerCoordinate: CLLocationCoordinate2D = {
        return MKMapPoint(x: serviceRect.midX, y: serviceRect.midY).coordinate
    }()

    /// Calculates the distance from the center of this region to the specified location.
    ///
    /// - Parameter location: The location to which we will calculate a distance.
    /// - Returns: The distance in meters.
    public func distanceFrom(location: CLLocation) -> CLLocationDistance {
        let centerLocation = CLLocation(latitude: centerCoordinate.latitude, longitude: centerCoordinate.longitude)
        return location.distance(from: centerLocation)
    }

    /// Determines whether the specified location is within this region's `serviceRect`.
    ///
    /// - Parameter location: The location to calculate inclusion in this region. Optional. If `nil` is provided, then this method will always return `false`.
    /// - Returns: True if the location is within `serviceRect` and false otherwise.
    public func contains(location: CLLocation?) -> Bool {
        guard let location = location else {
            return false
        }

        let point = MKMapPoint(location.coordinate)
        return serviceRect.contains(point)
    }

    // MARK: - Fare Payment

    public var supportsMobileFarePayment: Bool {
        paymentiOSAppURLScheme != nil
    }

    public var paymentAppDoesNotCoverFullRegion: Bool {
        paymentWarningTitle != nil && paymentWarningBody != nil
    }

    public var paymentAppDeepLinkURL: URL? {
        guard let paymentiOSAppURLScheme = paymentiOSAppURLScheme else {
            return nil
        }

        return URL(string: String(format: "%@://onebusaway", paymentiOSAppURLScheme))
    }
}

// MARK: - Open311Server

/// Defines an Open311 server, which is supported in some OBA regions.
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
        jurisdictionID = try? container.decodeIfPresent(String.self, forKey: .jurisdictionID)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        baseURL = try container.decode(URL.self, forKey: .baseURL)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try? container.encode(jurisdictionID, forKey: .jurisdictionID)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(baseURL, forKey: .baseURL)
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? Open311Server else { return false }
        return jurisdictionID == rhs.jurisdictionID &&
            apiKey == rhs.apiKey &&
            baseURL == rhs.baseURL
    }
}
