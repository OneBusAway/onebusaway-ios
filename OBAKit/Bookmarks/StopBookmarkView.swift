//
//  StopBookmarkView.swift
//  OBAKit
//
//  Created by Alan Chu on 10/6/21.
//

import SwiftUI

struct StopBookmarkView: View {
    @State var viewModel: StopBookmarkViewModel

    var body: some View {
        VStack(alignment: .leading) {
            RouteTypeLabelView(labelText: "Stop #\(viewModel.stopID)", routeType: viewModel.primaryRouteType)
            Text(viewModel.name)
                .font(.headline)
        }
    }
}

struct StopBookmarkView_Previews: PreviewProvider {
    static var previews: some View {
        List {
            StopBookmarkView(viewModel: .soundTransitUDistrict)
            StopBookmarkView(viewModel: .ferrySeattle)
        }
    }
}
