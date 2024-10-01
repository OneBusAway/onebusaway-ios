//
//  RegionPickerLocationAuthorizationView.swift
//  OBAKit
//
//  Created by Alan Chu on 2/3/23.
//

import SwiftUI
import OBAKitCore
import CoreLocationUI

/// Asks the user for one-time location authorization.
public struct RegionPickerLocationAuthorizationView<Provider: RegionProvider>: View, OnboardingView {
    @ObservedObject var regionProvider: Provider

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
                // LocationButton API is picky, so this button won't stretch across the width of the screen.
                LocationButton {
                    regionProvider.automaticallySelectRegion = true
                    dismiss()
                }
                .cornerRadius(8)
                .labelStyle(.titleAndIcon)
                .foregroundColor(.white)
            }
            .symbolVariant(.fill)
            .tint(.blue) // .accentColor might fail LocationButton's contrast test, so we'll just use the standard blue.
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
