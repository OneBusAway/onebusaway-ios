//
//  AppDelegate.m
//  OBANetworking
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

#import "AppDelegate.h"
@import OBAAppKit;

#import "ViewController.h"
#import "PermissionPromptViewController.h"

@interface AppDelegate ()<OBAApplicationDelegate>
@property(nonatomic,strong) OBAApplication *app;
@property(nonatomic,strong) ViewController *demoViewController;
@end

@implementation AppDelegate

- (instancetype)init {
    self = [super init];

    if (self) {
        NSURL *regionsBaseURL = [NSURL URLWithString:@"http://regions.onebusaway.org"];
        NSString *apiKey = @"test";
        NSString *uuid = NSUUID.UUID.UUIDString;
        NSString *appVersion = @"1.0.test";

        OBAAppConfig *appConfig = [[OBAAppConfig alloc] initWithRegionsBaseURL:regionsBaseURL apiKey:apiKey uuid:uuid appVersion:appVersion];
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

- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

#pragma mark - OBAApplicationDelegate

- (void)applicationReloadRootInterface:(OBAApplication*)application {
    if (application.showPermissionPromptUI) {
        PermissionPromptViewController *promptViewController = [[PermissionPromptViewController alloc] initWithLocationService:application.locationService];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:promptViewController];

        self.window.rootViewController = nav;
    }
    else {
        self.demoViewController = [[ViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:self.demoViewController];
        self.window.rootViewController = nav;
    }
}

@end
