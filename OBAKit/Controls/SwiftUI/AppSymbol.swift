//
//  AppSymbol.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation

/// Centralised SF Symbol names used across the SwiftUI surfaces.
///
/// Use this for symbols whose *semantic role* recurs across views (loading,
/// error, retry, search, etc.). View-private symbols that name a single
/// concrete state in one screen can still live in a file-local `Symbol`
/// enum next to that view; promote them here once a second consumer
/// appears. The UIKit equivalent for `UIImage`-based icons is `Icons`.
enum AppSymbol {

    // MARK: - Generic status

    /// "Something went wrong." Use for error-state placeholders.
    static let error = "exclamationmark.triangle"

    /// Generic loading / in-progress indicator. Also doubles as the canonical
    /// refresh/retry glyph because Apple uses the same symbol for both.
    static let loading = "arrow.clockwise"

    /// "Try again." Same glyph as `loading` by design — both communicate
    /// "this will fire a fresh fetch."
    static let retry = "arrow.clockwise"

    // MARK: - Search

    /// Search field icon / "no search results" placeholder.
    static let search = "magnifyingglass"

    // MARK: - Location

    /// "Location services unavailable" / permission-denied state.
    static let locationUnavailable = "location.slash"

    /// "Finding your location" / acquiring a fix.
    static let locationFinding = "location.viewfinder"

    // MARK: - Transit

    /// Bus icon. Used for transit-related empty states.
    static let bus = "bus"

    /// "No real-time tracking available." Crossed-out broadcast antenna.
    static let noRealtime = "antenna.radiowaves.left.and.right.slash"
}
