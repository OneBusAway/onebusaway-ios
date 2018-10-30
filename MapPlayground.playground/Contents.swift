//: A MapKit based Playground

import OBANetworkingKit
import MapKit
import PlaygroundSupport

PlaygroundPage.current.needsIndefiniteExecution = true

let baseURL = URL(string: "http://api.pugetsound.onebusaway.org")!
let apiKey = "test"
let uuid = UUID().uuidString
let appVersion = "playground"
let queue = OperationQueue()
let apiService = RESTAPIService(baseURL: baseURL, apiKey: apiKey, uuid: uuid, appVersion: appVersion, networkQueue: queue)
let modelService = RESTAPIModelService(apiService: apiService, dataQueue: queue)

apiService.getAgenciesWithCoverage { (op) in
    if let entries = op.entries {
        for a in entries {
            print("Agency: \(a)")
        }
    }
}

//let appleParkWayCoordinates = CLLocationCoordinate2DMake(37.334922, -122.009033)
//
//// Now let's create a MKMapView
//let mapView = MKMapView(frame: CGRect(x:0, y:0, width:800, height:800))
//
//// Define a region for our map view
//var mapRegion = MKCoordinateRegion()
//
//let mapRegionSpan = 0.02
//mapRegion.center = appleParkWayCoordinates
//mapRegion.span.latitudeDelta = mapRegionSpan
//mapRegion.span.longitudeDelta = mapRegionSpan
//
//mapView.setRegion(mapRegion, animated: true)
//
//// Create a map annotation
//let annotation = MKPointAnnotation()
//annotation.coordinate = appleParkWayCoordinates
//annotation.title = "Apple Inc."
//annotation.subtitle = "One Apple Park Way, Cupertino, California."
//
//mapView.addAnnotation(annotation)
//
//// Add the created mapView to our Playground Live View
//PlaygroundPage.current.liveView = mapView
