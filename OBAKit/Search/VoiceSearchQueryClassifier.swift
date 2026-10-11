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

    // A few cues per language the app ships. Matching is first-prefix-wins, so
    // the lists are sorted longest-first: "tuyến xe buýt 7" must strip the whole
    // phrase, not just "tuyến", and "línea" must not lose to a shorter cue.
    private static let routeCues = longestFirst([
        "route", "bus", "line",                         // en (also fr "bus")
        "ruta", "línea", "linea", "autobús", "autobus", // es
        "ligne",                                        // fr
        "autobus",                                      // it ("linea" above)
        "linia",                                        // pl
        "linha", "rota", "ônibus", "onibus",            // pt-BR
        "маршрут", "линия", "автобус",                  // ru
        "tuyến xe buýt", "tuyến", "xe buýt",            // vi
        "خط", "مسار", "الحافلة", "حافلة", "باص",        // ar
        "linya",                                        // fil ("ruta", "bus" above)
        "노선", "버스", "路線", "线路", "公交"              // ko, zh
    ])

    private static let vehicleCues = longestFirst([
        "vehicle",
        "vehículo", "véhicule", "veicolo", "pojazd",
        "veículo", "veiculo",
        "транспорт",
        "phương tiện",
        "المركبة", "مركبة",
        "sasakyan",
        "车辆", "車輛", "차량"
    ])

    private static func longestFirst(_ cues: [String]) -> [String] {
        // Dedupe (es and it share "autobus") and keep the order stable for ties.
        var seen = Set<String>()
        return cues.filter { seen.insert($0).inserted }
            .enumerated()
            .sorted { ($0.element.count, $1.offset) > ($1.element.count, $0.offset) }
            .map(\.element)
    }

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
