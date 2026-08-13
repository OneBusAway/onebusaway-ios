//
//  UIViewScrollViewSearchTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Testing
import UIKit
@testable import OBAKit

/// `UIView.nearestDescendantScrollView()` is how the stop sheet gets a handle on the scroll
/// view backing a SwiftUI `List`, since SwiftUI exposes none. These tests pin the two
/// properties the caller depends on: it finds the *shallowest* scroll view, and it reports
/// absence rather than trapping.
@MainActor
@Suite(.serialized)
final class UIViewScrollViewSearchTests {

    @Test func `Returns nil when hierarchy has no scroll view`() {
        let root = UIView()
        let child = UIView()
        root.addSubview(child)
        child.addSubview(UILabel())

        #expect(root.nearestDescendantScrollView() == nil)
    }

    @Test func `Returns receiver when receiver is a scroll view`() {
        let scrollView = UIScrollView()
        #expect(scrollView.nearestDescendantScrollView() === scrollView)
    }

    @Test func `Finds nested scroll view`() {
        let root = UIView()
        let middle = UIView()
        let scrollView = UIScrollView()

        root.addSubview(middle)
        middle.addSubview(scrollView)

        #expect(root.nearestDescendantScrollView() === scrollView)
    }

    /// The search must be breadth-first. A SwiftUI `List`'s rows can themselves contain scroll
    /// views; tracking one of those instead of the list would make the sheet resize off a
    /// single row's scrolling.
    @Test func `Prefers shallower scroll view over one nested deeper in an earlier branch`() {
        let root = UIView()

        // Earlier branch, deeper scroll view — a row's own scroll view.
        let firstBranch = UIView()
        let deepContainer = UIView()
        let deepScrollView = UIScrollView()
        deepContainer.addSubview(deepScrollView)
        firstBranch.addSubview(deepContainer)

        // Later branch, shallower scroll view — the list itself.
        let shallowScrollView = UIScrollView()

        root.addSubview(firstBranch)
        root.addSubview(shallowScrollView)

        #expect(root.nearestDescendantScrollView() === shallowScrollView)
    }

    /// `UITableView` and `UICollectionView` are the concrete types SwiftUI actually produces.
    @Test func `Finds collection view`() {
        let root = UIView()
        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: UICollectionViewFlowLayout()
        )
        root.addSubview(collectionView)

        #expect(root.nearestDescendantScrollView() === collectionView)
    }
}
