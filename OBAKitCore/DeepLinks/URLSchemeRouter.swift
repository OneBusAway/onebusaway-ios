//
//  URLSchemeRouter.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// A data object for viewing a stop from decoding an URL with `URLSchemeRouter`.
public struct StopURLData {
    public let stopID: StopID
    public let regionID: Int
}

/// `AddRegionURLData` is a data structure that encapsulates the information needed to add a new region
/// through a deep link. It contains the name of the region, the URL to the OneBusAway (OBA) server, and an optional
/// URL to the OpenTripPlanner (OTP) server.
///
/// - Parameters:
///   - name: The name of the region to be added. This is a human-readable string that identifies the region.
///   - obaURL: The URL to the OneBusAway (OBA) server for the region. This URL is used to access transit data.
///   - otpURL: An optional URL to the OpenTripPlanner (OTP) server. If provided, it can be used for trip planning.
///             If nil, it indicates that the region does not support OTP or that the URL was not provided.
public struct AddRegionURLData {
    public let name: String
    public let obaURL: URL
    public let otpURL: URL?
}

/// `URLType` represents the types of URLs that the `URLSchemeRouter` can handle.
/// It distinguishes between viewing a stop and adding a region through deep linking.
///
/// - viewStop: A URL type for viewing details of a specific stop.
///   Contains a `StopURLData` object with the stop ID and region ID.
/// - addRegion: A URL type for adding a new region.
///   Contains an optional `AddRegionURLData` object with the necessary information for adding the region.
///   If the data is nil, it indicates that the URL didn't contain valid or complete data for adding a region.
public enum URLType {
    case viewStop(StopURLData)
    case addRegion(AddRegionURLData?)
}
/// Provides support for deep linking into the app by way of a custom URL scheme.
///
/// Custom URL scheme deep linking (e.g. `onebusaway://view-stop?region_id=1&stop_id=12345`)
/// is the most reliable way to perform deep linking into the iOS app from an extension like the Today View.
/// The only reason we don't use it everywhere is because the URLs generated are completely useless unless
/// their recipient has a compatible version of OneBusAway installed on their device.
public class URLSchemeRouter: NSObject {
    /// The app bundle's URL scheme for extensions.
    private let scheme: String

    private let viewStopHost = "view-stop"
    private let addRegionHost = "add-region"

    /// Creates a new URL Scheme Router.
    /// - Parameter scheme: The app bundle's `extensionURLScheme` value.
    public init(scheme: String) {
        self.scheme = scheme
    }

    /// Decode URL Types based on host
    public func decodeURLType(from url: URL) -> URLType? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        switch components.host {
        case viewStopHost:
            return decodeViewStop(from: components)
        case addRegionHost:
            return decodeAddRegion(from: components)
        default:
            return nil
        }
    }

    // MARK: - Stop URLs
    /// Encodes the ID for a Stop along with its Region ID into an URL with the scheme `extensionURLScheme`.
    /// - Parameters:
    ///   - stopID: The ID for the Stop.
    ///   - regionID: The ID for the Region that hosts the Stop.
    public func encodeViewStop(stopID: StopID, regionID: Int) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = viewStopHost
        components.queryItems = [URLQueryItem(name: "stopID", value: stopID), URLQueryItem(name: "regionID", value: String(regionID))]

        return components.url!
    }

    /// Decodes a `StopURLData` struct from `url`, which can be used to display a `StopViewController`.
    /// - Parameter url: An URL created from calling `URLSchemeRouter.encode()`
    private func decodeViewStop(from components: URLComponents) -> URLType? {
        guard
            let stopID = components.queryItem(named: "stopID")?.value,
            let regionIDString = components.queryItem(named: "regionID")?.value,
            let regionID = Int(regionIDString) else {
                return nil
        }
        return .viewStop(StopURLData(stopID: stopID, regionID: regionID))
    }

    // MARK: - Add Region URLs
    /// Encodes the OBA URL for adding custom region  along with its Name into an URL with the scheme `extensionURLScheme`. It also has optional OTP URL
    private func decodeAddRegion(from components: URLComponents) -> URLType? {
        guard
            let name = components.queryItem(named: "name")?.value,
            let obaUrlString = components.queryItem(named: "oba-url")?.value,
            let obaURL = validateAndCreateURL(from: obaUrlString) else {
            return .addRegion(nil)
        }
        
        var otpURL: URL?
        if let otpUrlString = components.queryItem(named: "otp-url")?.value {
            otpURL = validateAndCreateURL(from: otpUrlString)
        }

        return .addRegion(AddRegionURLData(name: name, obaURL: obaURL, otpURL: otpURL))
    }

    /// Validates that a URL string represents a proper URL with a scheme or is a valid path
    private func validateAndCreateURL(from urlString: String) -> URL? {
        // First check if the string is blank (empty or whitespace only)
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        // Try to create URL
        guard let url = URL(string: urlString) else {
            return nil
        }

        // Validate the URL has either a scheme or is a path
        if url.scheme != nil || urlString.hasPrefix("/") {
            return url
        }

        return nil
    }
}
