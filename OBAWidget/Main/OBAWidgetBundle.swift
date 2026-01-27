//
//  OBAWidgetBundle.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-12.
//

import WidgetKit
import SwiftUI

@main
struct CBWidgetBundle: WidgetBundle {
    var body: some Widget {
        OBAWidget()
        // Add the Live Activity widget
        if #available(iOS 16.2, *) {
            TripLiveActivity()
        }
    }
}
