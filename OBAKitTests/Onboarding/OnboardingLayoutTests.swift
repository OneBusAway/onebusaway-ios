//
//  OnboardingLayoutTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import SwiftUI
@testable import OBAKit

/// Onboarding keeps a readable column on iPad and leaves iPhone's layout alone.
@Suite(.serialized)
struct OnboardingLayoutTests {

    @Test func `Regular width caps the column at the readable width`() {
        #expect(OnboardingLayout.maxContentWidth(for: .regular) == OnboardingLayout.readableWidth)
    }

    @Test func `Compact width leaves the column unconstrained`() {
        #expect(OnboardingLayout.maxContentWidth(for: .compact) == nil)
    }

    @Test func `An unknown size class leaves the column unconstrained`() {
        #expect(OnboardingLayout.maxContentWidth(for: nil) == nil)
    }

    /// Wider than any iPhone in portrait, so the cap can't bite there even if
    /// the size class reads regular, and narrow enough to read on iPad.
    @Test func `The readable width is wider than an iPhone and narrower than an iPad`() {
        #expect(OnboardingLayout.readableWidth > 440)
        #expect(OnboardingLayout.readableWidth < 744)
    }
}
