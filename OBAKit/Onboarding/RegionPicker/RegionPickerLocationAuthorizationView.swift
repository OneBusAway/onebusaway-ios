//
//  RegionPickerLocationAuthorizationView.swift
//  OBAKit
//
//  Created by Alan Chu on 2/3/23.
//

import SwiftUI
import OBAKitCore

/// Asks the user for "while in use" location authorization so the app can
/// automatically select their region. Unlike a one-time authorization, this
/// grant persists across launches.
public struct RegionPickerLocationAuthorizationView<Provider: RegionProvider>: View, OnboardingView {
    @ObservedObject var regionProvider: Provider

    @Environment(\.coreApplication) var application

    public var dismissBlock: VoidBlock?
    @Environment(\.dismiss) public var dismissAction

    public init(regionProvider: Provider, dismissBlock: VoidBlock? = nil) {
        self.regionProvider = regionProvider
        self.dismissBlock = dismissBlock
    }

    public var body: some View {
        List {
            Text(OBALoc("location_permission_bulletin.description_text", value: "Please allow the app to access your location to make it easier to find your transit stops.", comment: "Description of why we need location services"))
                .listRowSeparator(.hidden)
        }
        .listSectionSeparator(.hidden)
        .listStyle(.plain)
        .safeAreaInset(edge: .top) {
            OnboardingHeaderView(imageSystemName: "mappin", headerText: OBALoc("location_permission_bulletin.title", value: "Welcome!", comment: "Title of the alert that appears to request your location."))
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 16) {
                Button {
                    regionProvider.automaticallySelectRegion = true
                    application.locationService.requestInUseAuthorization()
                    dismiss()
                } label: {
                    Label(OBALoc("location_permission_bulletin.use_location_button_text", value: "Use My Location", comment: "Button the user taps to grant access to their location."), systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    regionProvider.automaticallySelectRegion = false
                    dismiss()
                } label: {
                    Label(OBALoc("location_permission_bulletin.do_not_use_location_button_text", value: "Not Now", comment: "Button the user can tap on to decline access to their location."), systemImage: "location.slash")
                }
            }
            .symbolVariant(.fill)
            .tint(.blue)
        }
        .navigationBarHidden(true)
        .padding()
    }
}

#if DEBUG
struct RegionPickerLocationAuthorizationView_Previews: PreviewProvider {
    static var previews: some View {
        RegionPickerLocationAuthorizationView(regionProvider: Previews_SampleRegionProvider())
    }
}

#endif
