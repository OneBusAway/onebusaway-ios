//
//  URLSchemeRouter.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 2/12/20.
//

import Foundation

/// A data object for viewing a stop from decoding an URL with `URLSchemeRouter`.
public struct StopURLData {
    public let stopID: StopID
    public let regionID: Int
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

    /// Creates a new URL Scheme Router.
    /// - Parameter scheme: The app bundle's `extensionURLScheme` value.
    public init(scheme: String) {
        self.scheme = scheme
    }

    // MARK: - Stop URLs

    private let viewStopHost = "view-stop"

    /// Encodes the ID for a Stop along with its Region ID into an URL with the scheme `extensionURLScheme`.
    /// - Parameters:
    ///   - stopID: The ID for the Stop.
    ///   - regionID: The ID for the Region that hosts the Stop.
    public func encode(stopID: StopID, regionID: Int) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = viewStopHost
        components.queryItems = [URLQueryItem(name: "stopID", value: stopID), URLQueryItem(name: "regionID", value: String(regionID))]

        return components.url!
    }

    /// Decodes a `StopURLData` struct from `url`, which can be used to display a `StopViewController`.
    /// - Parameter url: An URL created from calling `URLSchemeRouter.encode()`
    public func decode(url: URL) -> StopURLData? {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.host == viewStopHost,
            let stopID = components.queryItem(named: "stopID")?.value,
            let regionIDString = components.queryItem(named: "regionID")?.value,
            let regionID = Int(regionIDString)
        else {
            return nil
        }

        return StopURLData(stopID: stopID, regionID: regionID)
    }
}
