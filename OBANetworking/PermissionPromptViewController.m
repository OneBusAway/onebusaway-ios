//
//  PermissionPromptViewController.m
//  OBANetworking
//
//  Created by Aaron Brethorst on 11/15/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

#import "PermissionPromptViewController.h"

@interface PermissionPromptViewController ()
@property(nonatomic,strong) OBALocationService *locationService;
@end

@implementation PermissionPromptViewController

- (instancetype)initWithLocationService:(OBALocationService*)locationService {
    self = [super initWithNibName:@"PermissionPromptViewController" bundle:nil];

    if (self) {
        _locationService = locationService;
    }
    return self;
}

- (IBAction)authorizeLocationAccess:(id)sender {
    [self.locationService requestInUseAuthorization];
}

@end
