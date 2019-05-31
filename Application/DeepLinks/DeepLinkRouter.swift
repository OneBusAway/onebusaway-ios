//
//  DeepLinkRouter.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 5/31/19.
//

import Foundation

/// Creates deep links (i.e. Universal Links) to OBA-associated web pages.
@objc(OBADeepLinkRouter) public class DeepLinkRouter: NSObject {
    private let baseURL: URL

    /// Initializes the `DeepLinkRouter`
    ///
    /// - Parameter baseURL: The deep link server host. Usually this is `http://alerts.onebusaway.org`.
    public init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// Creates a link to the OneBusAway stop page for the specified stop and region.
    ///
    /// - Parameters:
    ///   - stop: The stop for which a link will be created.
    ///   - region: The region in which the link will exist.
    public func url(for stop: Stop, region: Region) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.path = String(format: "/regions/%d/stops/%@", region.regionIdentifier, stop.id)

        return components.url
    }
}
