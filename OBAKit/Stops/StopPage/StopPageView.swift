//
//  StopPageView.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import SwiftUI
import OBAKitCore

/// Root view of the redesigned Stop page. This is the ONLY view that observes
/// `StopViewModel`; every subview receives plain values so the VM's frequent
/// `@Published` churn (refresh + status timers) re-evaluates one shallow body.
struct StopPageView: View {
    @ObservedObject var viewModel: StopViewModel

    var body: some View {
        List {
            Section {
                Text(viewModel.stop?.name ?? "…")
            }
        }
        .listStyle(.insetGrouped)
        .task { await viewModel.start() }
        .onDisappear { viewModel.deactivate() }
        .refreshable { await viewModel.refresh() }
    }
}
