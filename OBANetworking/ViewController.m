//
//  ViewController.m
//  OBANetworking
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

#import "ViewController.h"
@import OBANetworkingKit;

@interface ViewController ()
@property(nonatomic,strong) OBARESTAPIService *apiService;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    NSURL *URL = [NSURL URLWithString:@"http://api.pugetsound.onebusaway.org/"];
    self.apiService = [[OBARESTAPIService alloc] initWithBaseURL:URL apiKey:@"org.onebusaway.iphone" uuid:@"BD88D98C-A72D-47BE-8F4A-C60467239736" appVersion:@"20181001.23"];

    CurrentTimeOperation *operation = [self.apiService getCurrentTimeWithCompletion:^(OBARESTAPIOperation * op) {
        NSLog(@"Current Time: %@", ((CurrentTimeOperation*)op).currentTime);
    }];(void)operation;
}


@end
