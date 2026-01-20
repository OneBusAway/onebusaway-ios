//
//  ExternalSurveyURLBuilder.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

final public class ExternalSurveyURLBuilder {

    private let userStore: UserDataStore

    private let application: CoreApplication

    private let userID: String
    private var stop: Stop?

    public init(userStore: UserDataStore, userID: String, application: CoreApplication) {
        self.userStore = userStore
        self.userID = userID
        self.application = application
    }

    public func buildURL(for survey: Survey, stop: Stop?) -> URL? {
        guard let baseURL = survey.questions.first?.content.url,
              var components = URLComponents(string: baseURL)
        else {
            return nil
        }

        var queryItems: [URLQueryItem] = components.queryItems ?? []

        if let keys = survey.questions.first?.content.embeddedDataFields {
            setEmbeddedKeyValue(to: &queryItems, for: keys)
        }

        components.queryItems = queryItems
        return components.url
    }

    private func setEmbeddedKeyValue(to items: inout [URLQueryItem], for keys: [String]) {
        for key in keys {
            if let value = getEmbeddedKeyValue(key) {
                items.append(.init(name: key, value: value))
            }
        }
    }

    private func getEmbeddedKeyValue(_ key: String) -> String? {
        return switch key {
        case "user_id":
            userID
        case "region_id":
            getRegionID()
        case "route_id":
            getRouteId()
        case "stop_id":
            getStopId()
        case "recent_stop_ids":
            getRecentStopIds()
        case "current_location":
            getCurrentLocation()
        default:
            nil
        }
    }

    private func getRegionID() -> String? {
        guard let regionId = application.currentRegion?.regionIdentifier else {
            return nil
        }
        return "\(regionId)"
    }

    private func getRouteId() -> String? {
        guard let stop, !stop.routeIDs.isEmpty else { return nil }
        return stop.routeIDs.joined(separator: ",")
    }

    private func getStopId() -> String? {
        guard let stop else { return nil }
        return "\(stop.id)"
    }

    private func getRecentStopIds() -> String? {
        userStore.recentStops.map { $0.id }.joined(separator: ",")
    }

    private func getCurrentLocation() -> String? {
        guard let coordinate = application.locationService.currentLocation?.coordinate else {
            return nil
        }
        return "\(coordinate.latitude),\(coordinate.longitude)"
    }
}
