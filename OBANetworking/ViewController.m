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
@property(nonatomic,strong) OBANetworkRequestBuilder *networkRequestBuilder;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    NSURL *URL = [NSURL URLWithString:@"http://api.pugetsound.onebusaway.org/"];
    self.networkRequestBuilder = [[OBANetworkRequestBuilder alloc] initWithBaseURL:URL];

    CurrentTimeOperation *operation = [self.networkRequestBuilder getCurrentTimeWithCompletion:^(CurrentTimeOperation * op) {
        NSLog(@"%@", op);
    }];(void)operation;
}


@end
