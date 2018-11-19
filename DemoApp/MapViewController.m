//
//  MapViewController.m
//  OBANetworking
//
//  Created by Aaron Brethorst on 11/15/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

#import "MapViewController.h"
@import MapKit;
@import OBALocationKit;

@interface MapViewController ()<MKMapViewDelegate, OBALocationServiceDelegate>
@property(nonatomic,strong,readonly) OBALocationService *locationService;
@property(nonatomic,strong,readonly) OBARegionsService *regionsService;
@property(nonatomic,strong) OBAApplication *application;
@property(nonatomic,strong) MKMapView *mapView;
@end

@implementation MapViewController

- (instancetype)initWithApplication:(OBAApplication*)application {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _application = application;
        [_application.locationService addDelegate:self];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self.view addSubview:self.mapView];
}

#pragma mark - Services

- (OBALocationService*)locationService {
    return self.application.locationService;
}

- (OBARegionsService*)regionsService {
    return self.application.regionsService;
}

#pragma mark - UI

- (MKMapView*)mapView {
    if (!_mapView) {
        _mapView = [[MKMapView alloc] initWithFrame:self.view.bounds];
        _mapView.delegate = self;
        _mapView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        _mapView.showsUserLocation = self.application.locationService.isLocationUseAuthorized;
    }

    return _mapView;
}

#pragma mark - Location Service Delegate

- (void)locationService:(OBALocationService *)service authorizationStatusChanged:(CLAuthorizationStatus)status {
    self.mapView.showsUserLocation = self.application.locationService.isLocationUseAuthorized;
}

- (void)locationService:(OBALocationService *)service locationChanged:(CLLocation *)location {
    //
}

- (void)locationService:(OBALocationService *)service headingChanged:(CLHeading *)heading {
    //
}

- (void)locationService:(OBALocationService *)service errorReceived:(NSError *)error {
    //
}

@end
