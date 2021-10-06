//
//  RouteTypeLabelView.swift
//  OBAKit
//
//  Created by Alan Chu on 10/6/21.
//

import SwiftUI
import OBAKitCore

struct RouteTypeLabelView: View {
    let labelText: String
    let routeType: Route.RouteType

    var body: some View {
        Label {
            Text(labelText)
        } icon: {
            Image(uiImage: Icons.transportIcon(from: routeType))
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .frame(width: 24)
        }
        .labelStyle(.titleAndIcon)
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
}

struct RouteTypeLabelView_Previews: PreviewProvider {
    static var previews: some View {
        List {
            RouteTypeLabelView(labelText: "550", routeType: .bus)
            RouteTypeLabelView(labelText: "Stop #12345679", routeType: .lightRail)
        }
    }
}
