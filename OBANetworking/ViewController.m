//
//  ViewController.m
//  OBANetworking
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

#import "ViewController.h"
@import OBANetworkingKit;
@import OBALocationKit;

@interface ViewController ()
@property(nonatomic,strong) OBAApplication *application;
@property(nonatomic,strong) OBARESTAPIService *apiService;
@property(nonatomic,strong) OBALocationService *locationService;
@end

@implementation ViewController

- (instancetype)initWithApplication:(OBAApplication*)application {
    self = [super initWithNibName:nil bundle:nil];

    if (self) {
        _application = application;
    }

    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.whiteColor;

    NSURL *URL = [NSURL URLWithString:@"http://api.pugetsound.onebusaway.org/"];
    self.apiService = [[OBARESTAPIService alloc] initWithBaseURL:URL apiKey:@"org.onebusaway.iphone" uuid:@"BD88D98C-A72D-47BE-8F4A-C60467239736" appVersion:@"20181001.23"];

    CurrentTimeOperation *operation = [self.apiService getCurrentTime];
    __weak typeof(operation) weakOp = operation;
    operation.completionBlock = ^{
        NSLog(@"Current Time: %@", weakOp.currentTime);
    };
}

@end
