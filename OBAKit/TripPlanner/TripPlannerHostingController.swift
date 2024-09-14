//
//  TripPlannerHostingView.swift
//  OBAKit
//
//  Created by Hilmy Veradin on 14/09/24.
//

import UIKit
import SwiftUI
import OBAKitCore
import OTPKit

class TripPlannerHostingController: UIHostingController<AnyView> {

    init(tripPlannerService: TripPlannerService) {
        let rootView = AnyView(
            TripPlannerView()
            .environment(tripPlannerService)
            .environment(OriginDestinationSheetEnvironment())
        )

        super.init(rootView: rootView)

        title = Strings.tripPlanner
        tabBarItem.image = Icons.tripPlannerTabIcon
        tabBarItem.selectedImage = Icons.tripPlannerSelectedTabIcon

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        tabBarItem.scrollEdgeAppearance = appearance
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
