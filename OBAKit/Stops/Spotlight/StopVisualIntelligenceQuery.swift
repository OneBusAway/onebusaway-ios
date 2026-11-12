//
//  StopVisualIntelligenceQuery.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

// VisualIntelligence is in the device SDK only, not the simulator's.
#if canImport(VisualIntelligence)
import AppIntents
import CoreVideo
import OBAKitCore
import Vision
import VisualIntelligence

/// Puts the stops around the rider in visual intelligence's results when they
/// point the camera at a stop (#1555). A tapped stop opens through
/// `OpenStopIntent`, whose target is a `StopEntity`.
///
/// The camera image is read on the device for a stop code and then dropped:
/// it is never stored or sent anywhere.
@available(iOS 26.0, *)
nonisolated public struct StopVisualIntelligenceQuery: IntentValueQuery {
    public init() {}

    public func values(for input: SemanticContentDescriptor) async throws -> [StopEntity] {
        guard let loader = NearbyStopEntityLoader(bundle: .main) else {
            Logger.error("Visual intelligence stops: app group UserDefaults unavailable; offering no stops.")
            return []
        }
        let text = input.pixelBuffer.map(StopSignReader.text(in:)) ?? []
        return await loader.entities(recognizedText: text)
    }
}

/// Reads the text on a stop sign, for its stop code.
@available(iOS 26.0, *)
nonisolated enum StopSignReader {
    static func text(in pixelBuffer: CVReadOnlyPixelBuffer) -> [String] {
        pixelBuffer.withUnsafeBuffer { buffer in
            let request = VNRecognizeTextRequest()
            // Codes are digits and short words; speed matters more than prose.
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            do {
                try VNImageRequestHandler(cvPixelBuffer: buffer).perform([request])
            } catch {
                Logger.error("Visual intelligence stops: text recognition failed: \(error)")
                return []
            }
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }
    }
}
#endif // canImport(VisualIntelligence)
