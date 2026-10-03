//
//  MapViewController+StopCluster.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore
import UIKit

/// Tapping a cluster of stop pins.
///
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/515
extension MapViewController {

    /// Zooms in on a cluster that zooming can separate. Stops at the same spot
    /// stay clustered at any zoom, so for those it lists the stops instead.
    func selectStopCluster(_ cluster: MKClusterAnnotation, view: MKAnnotationView, in mapView: MKMapView) {
        let members = cluster.memberAnnotations

        guard StopCluster.areCoLocated(members.map(\.coordinate)) else {
            mapView.deselectAnnotation(cluster, animated: false)
            let enclosingRect = members.reduce(MKMapRect.null) {
                $0.union(MKMapRect(origin: MKMapPoint($1.coordinate), size: MKMapSize(width: 0, height: 0)))
            }
            let inset: CGFloat = 60
            mapView.setVisibleMapRect(
                enclosingRect,
                edgePadding: UIEdgeInsets(top: inset, left: inset, bottom: 200, right: inset),
                animated: true
            )
            return
        }

        let picker = UIAlertController(
            title: OBALoc("map_controller.stop_cluster_picker.title", value: "Choose a Stop", comment: "Title of the list shown when tapping a map pin that groups several stops at the same location."),
            message: nil,
            preferredStyle: .actionSheet
        )

        for stop in StopCluster.stops(in: members) {
            picker.addAction(UIAlertAction(title: StopCluster.pickerTitle(for: stop), style: .default) { [weak self] _ in
                guard let self else { return }
                self.application.analytics?.reportEvent(pageURL: "app://localhost/map", label: AnalyticsLabels.mapStopAnnotationTapped, value: nil)
                self.show(stop: stop, deselecting: cluster)
            })
        }

        picker.addAction(UIAlertAction(title: Strings.cancel, style: .cancel) { _ in
            mapView.deselectAnnotation(cluster, animated: true)
        })

        picker.popoverPresentationController?.sourceView = view
        picker.popoverPresentationController?.sourceRect = view.bounds

        present(picker, animated: true)
    }
}
