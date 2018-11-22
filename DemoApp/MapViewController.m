//
//  MapViewController.m
//  OBANetworking
//
//  Created by Aaron Brethorst on 11/15/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

#import "MapViewController.h"
@import MapKit;
@import OBANetworkingKit;
@import OBALocationKit;

@interface MapViewController ()<MKMapViewDelegate, OBALocationServiceDelegate>
@property(nonatomic,strong,readonly) OBALocationService *locationService;
@property(nonatomic,strong,readonly) OBARegionsService *regionsService;
@property(nonatomic,strong) OBAApplication *application;
@property(nonatomic,strong) MKMapView *mapView;
@property(nonatomic,strong) OBAMapRegionManager *mapRegionManager;

@property(nonatomic,assign) BOOL initialMapChangeMade;
@end

@implementation MapViewController

- (instancetype)initWithApplication:(OBAApplication*)application {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _application = application;
        [_application.locationService addDelegate:self];

        _mapRegionManager = [[OBAMapRegionManager alloc] initWithApplication:_application];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    MKMapView *mapView = self.mapRegionManager.mapView;
    mapView.frame = self.view.bounds;
    mapView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:mapView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    CLLocation *loc = self.locationService.currentLocation;
    OBARegion *currentRegion = self.regionsService.currentRegion;

    if (currentRegion && loc) {
        self.initialMapChangeMade = YES;
        [self.mapRegionManager.mapView setRegion:MKCoordinateRegionMake(loc.coordinate, MKCoordinateSpanMake(0.008, 0.008)) animated:NO];
    }
    else if (currentRegion && !loc) {
        self.mapRegionManager.mapView.visibleMapRect = currentRegion.serviceRect;
    }
    else if (!currentRegion) {
        // panic?
    }
}

#pragma mark - Services

- (OBALocationService*)locationService {
    return self.application.locationService;
}

- (OBARegionsService*)regionsService {
    return self.application.regionsService;
}

- (OBARESTAPIModelService*)modelService {
    return self.application.restAPIModelService;
}

#pragma mark - Map View Delegate

- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated {
    
    StopsModelOperation *op = [self.modelService getStopsWithRegion:mapView.region];

}

#pragma mark - Location Service Delegate

- (void)locationService:(OBALocationService *)service authorizationStatusChanged:(CLAuthorizationStatus)status {
    self.mapView.showsUserLocation = self.application.locationService.isLocationUseAuthorized;
}

- (void)locationService:(OBALocationService *)service locationChanged:(CLLocation *)location {
    if (!self.initialMapChangeMade) {
        self.initialMapChangeMade = YES;
        [self.mapRegionManager.mapView setRegion:MKCoordinateRegionMake(location.coordinate, MKCoordinateSpanMake(0.008, 0.008)) animated:NO];
    }
}

- (void)locationService:(OBALocationService *)service headingChanged:(CLHeading *)heading {
    //
}

- (void)locationService:(OBALocationService *)service errorReceived:(NSError *)error {
    //
}

@end
