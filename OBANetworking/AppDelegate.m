//
//  AppDelegate.m
//  OBANetworking
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

#import "AppDelegate.h"
@import OBAAppKit;

#import "MapViewController.h"
#import "PermissionPromptViewController.h"

@interface AppDelegate ()<OBAApplicationDelegate>
@property(nonatomic,strong) OBAApplication *app;
@property(nonatomic,strong) MapViewController *mapController;
@end

@implementation AppDelegate

- (instancetype)init {
    self = [super init];

    if (self) {
        NSURL *regionsBaseURL = [NSURL URLWithString:@"http://regions.onebusaway.org"];
        NSString *apiKey = @"test";
        NSString *uuid = NSUUID.UUID.UUIDString;
        NSString *appVersion = @"1.0.test";

        OBAAppConfig *appConfig = [[OBAAppConfig alloc] initWithRegionsBaseURL:regionsBaseURL apiKey:apiKey uuid:uuid appVersion:appVersion userDefaults:NSUserDefaults.standardUserDefaults];
        _app = [[OBAApplication alloc] initWithConfig:appConfig];
        _app.delegate = self;
    }

    return self;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    NSURLCache *urlCache = [[NSURLCache alloc] initWithMemoryCapacity:4 * 1024 * 1024 diskCapacity:20 * 1024 * 1024 diskPath:nil];
    [NSURLCache setSharedURLCache:urlCache];

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    [self applicationReloadRootInterface:self.app];
    [self.window makeKeyAndVisible];

    return YES;
}

#pragma mark - OBAApplicationDelegate

- (void)applicationReloadRootInterface:(OBAApplication*)application {
    if (application.showPermissionPromptUI) {
        PermissionPromptViewController *promptViewController = [[PermissionPromptViewController alloc] initWithLocationService:application.locationService];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:promptViewController];

        self.window.rootViewController = nav;
    }
    else {
        self.mapController = [[MapViewController alloc] initWithApplication:application];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:self.mapController];
        self.window.rootViewController = nav;
    }
}

@end
