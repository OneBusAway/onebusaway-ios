//
//  StopPageViewController.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit
import SwiftUI
import Combine
import OBAKitCore

/// Hosting shell for the redesigned SwiftUI Stop page. Owns UIKit-side chrome
/// (nav bar items, menus) and keeps parity entry points (`Previewable` etc.)
/// working while `FeatureFlags.useNewStopPageKey` is enabled.
///
/// The root view is `StopPageRootView`, a thin wrapper that applies
/// `.defaultAppStorage(application.userDefaults)` so the page's `@AppStorage`
/// shares the app-group suite with the legacy screen.
class StopPageViewController: UIHostingController<StopPageRootView>, AppContext {
    let application: Application
    let viewModel: StopViewModel
    private var cancellables = Set<AnyCancellable>()

    var bookmarkContext: Bookmark? {
        get { viewModel.bookmarkContext }
        set { viewModel.bookmarkContext = newValue }
    }

    var transferContext: TransferContext? {
        get { viewModel.transferContext }
        set { viewModel.transferContext = newValue }
    }

    convenience init(application: Application, stop: Stop) {
        self.init(application: application, stopID: stop.id, stop: stop)
    }

    convenience init(application: Application, stopID: StopID) {
        self.init(application: application, stopID: stopID, stop: nil)
    }

    private init(application: Application, stopID: StopID, stop: Stop?) {
        self.application = application
        self.viewModel = StopViewModel(application: application, stopID: stopID, stop: stop)

        // Seed with placeholder closures; `self` isn't available until super.init
        // returns, so the real closures (which capture `self`) are installed below.
        super.init(rootView: StopPageRootView(
            viewModel: viewModel,
            userDefaults: application.userDefaults,
            snapshotLoader: { _ in nil },
            onSelectAlert: { _ in }
        ))

        rootView = StopPageRootView(
            viewModel: viewModel,
            userDefaults: application.userDefaults,
            snapshotLoader: { [weak self] size in
                guard let self else { return nil }
                return await self.loadSnapshot(size: size)
            },
            onSelectAlert: { [weak self] alert in
                guard let self else { return }
                self.application.viewRouter.navigateTo(alert: alert, from: self)
            }
        )

        hidesBottomBarWhenPushed = false
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        viewModel.$stop
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stop in
                self?.title = stop.map(Formatters.formattedTitle(stop:)) ?? Strings.loading
            }
            .store(in: &cancellables)
        navigationItem.largeTitleDisplayMode = .never
    }

    /// Bridges the callback-based `MapSnapshotter` into async/await for the
    /// SwiftUI header. Mirrors `StopHeaderView`'s configuration (stop
    /// annotation, zoom, muted map) from `StopHeaderController.swift`.
    private func loadSnapshot(size: CGSize) async -> UIImage? {
        guard let stop = viewModel.stop, size.width > 0, size.height > 0 else { return nil }
        let factory = application.stopIconFactory
        let traits = traitCollection
        return await withCheckedContinuation { continuation in
            let snapshotter = MapSnapshotter(size: size, stopIconFactory: factory)
            snapshotter.snapshot(stop: stop, traitCollection: traits) { image in
                continuation.resume(returning: image)
            }
        }
    }
}
