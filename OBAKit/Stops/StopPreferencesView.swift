//
//  StopPreferencesView.swift
//  OBAKit
//
//  Created by Alan Chu on 11/9/21.
//

import Combine
import SwiftUI
import OBAKitCore

protocol StopPreferencesViewDelegate: AnyObject {
    func stopPreferences(stopID: StopID, updated stopPreferences: StopPreferences)
}

/// Provides a selectable list of routes to display for a given stop.
/// To use `StopPreferencesView`, it is recommended to use `StopPreferencesWrappedView` as
/// that is compatible with the current `OBAKitCore.StopPreferences`.
struct StopPreferencesView: View {
    @Environment(\.coreApplication) var application
    @Environment(\.presentationMode) var presentationMode

    @Binding var viewModel: StopPreferencesViewModel

    var body: some View {
        List(viewModel.availableRoutes, id: \.id, selection: $viewModel.selectedRoutes) { route in
            VStack(alignment: .leading) {
                Text(route.displayName)
                Text(route.agencyName)
                    .font(.footnote)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(OBALoc("stop_preferences_controller.title", value: "Filter Routes", comment: "Title of the Edit Stop preferences controller"))
        .toolbar {
            ToolbarItemGroup {
                Button(Strings.done) {
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }
}

/// A wrapped version of `StopPreferencesView` that is easier to use with `OBAKitCore.StopPreferences` and UIKit.
struct StopPreferencesWrappedView: View {
    @Environment(\.coreApplication) var application
    @State fileprivate var viewModel: StopPreferencesViewModel

    public weak var delegate: StopPreferencesViewDelegate?

    init(_ stop: Stop, initialHiddenRoutes: Set<RouteID>, delegate: StopPreferencesViewDelegate?) {
        self.delegate = delegate

        var preferencesViewModel = StopPreferencesViewModel(stop)
        preferencesViewModel.hiddenRoutes = initialHiddenRoutes
        self._viewModel = State(initialValue: preferencesViewModel)
    }

    var body: some View {
        NavigationView {
            StopPreferencesView(viewModel: $viewModel)
        }
        .onReceive(Just(viewModel.selectedRoutes), perform: { asdf in
            guard let delegate = delegate else {
                return
            }

            guard let region = application.currentRegion else {
                return
            }

            let sort = application.stopPreferencesDataStore.preferences(stopID: viewModel.stopID, region: region).sortType
            let stopPreferences = StopPreferences(sortType: sort, hiddenRoutes: viewModel.hiddenRoutes.allObjects)
            delegate.stopPreferences(stopID: viewModel.stopID, updated: stopPreferences)
        })
    }
}

struct StopPreferencesView_Previews: PreviewProvider {
    @State
    static var preferences = StopPreferencesViewModel(stopID: "1_4836", availableRoutes: [
        .init(id: "1_241", displayName: "241", agencyName: "Metro Transit"),
        .init(id: "1_240", displayName: "240", agencyName: "Metro Transit"),
        .init(id: "0_550", displayName: "550", agencyName: "Sound Transit")])

    static var previews: some View {
        NavigationView {
            StopPreferencesView(viewModel: $preferences)
        }
    }
}
