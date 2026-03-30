//
//  OBAWidgetBundle.swift
//  OBAWidget
//
//  Created by Manu on 2024-10-12.
//

import Foundation
import SwiftUI

@main
struct CBWidgetBundle: WidgetBundle {
    var body: some Widget {
        OBAWidget()
        if #available(iOS 16.2, *) {
            TransitLiveActivityWidget()
        }
    }
}
