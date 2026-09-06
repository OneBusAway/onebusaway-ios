//
//  VoiceSearchQueryClassifier.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Maps a spoken utterance to a `SearchRequest` for voice search (#1129).
enum VoiceSearchQueryClassifier {

    static func request(from utterance: String) -> SearchRequest {
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SearchRequest(query: "", type: .address)
        }

        if let remainder = strippingCue(from: trimmed, cues: Self.vehicleCues) {
            return SearchRequest(query: remainder.isEmpty ? trimmed : remainder, type: .vehicleID)
        }

        if let remainder = strippingCue(from: trimmed, cues: Self.routeCues) {
            return SearchRequest(query: remainder.isEmpty ? trimmed : remainder, type: .route)
        }

        if isMostlyStopNumber(trimmed) {
            return SearchRequest(query: trimmed, type: .stopNumber)
        }

        return SearchRequest(query: trimmed, type: .address)
    }

    // English first; a few locale cues for the languages the app ships.
    private static let routeCues = [
        "route", "bus",
        "linia", "ligne", "linea", "línea",
        "маршрут", "линия",
        "노선", "路線", "线路", "tuyến"
    ]

    private static let vehicleCues = [
        "vehicle",
        "pojazd", "vehículo", "véhicule",
        "транспорт", "车辆", "車輛", "차량"
    ]

    /// Cue match is case-insensitive; the returned remainder keeps the original
    /// casing (so "Route Rapid Ride D" searches `Rapid Ride D`, not lowercased).
    private static func strippingCue(from original: String, cues: [String]) -> String? {
        let lowercased = original.lowercased()
        for cue in cues {
            guard lowercased.hasPrefix(cue) else { continue }
            if lowercased.count == cue.count {
                return ""
            }
            let boundaryIndex = lowercased.index(lowercased.startIndex, offsetBy: cue.count)
            let boundary = lowercased[boundaryIndex]
            // Avoid matching "business" as "bus".
            guard boundary.isWhitespace || boundary.isPunctuation || boundary.isNumber else {
                continue
            }
            let originalBoundary = original.index(original.startIndex, offsetBy: cue.count)
            let remainder = original[originalBoundary...]
                .drop(while: { $0.isWhitespace || $0.isPunctuation })
            return String(remainder).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func isMostlyStopNumber(_ text: String) -> Bool {
        let compact = text.filter { !$0.isWhitespace }
        guard !compact.isEmpty else { return false }
        let digits = compact.filter(\.isNumber)
        guard digits.count >= 2 else { return false }
        let significant = compact.filter { $0.isNumber || $0 == "_" || $0 == "-" }
        return Double(significant.count) / Double(compact.count) >= 0.7
    }
}
