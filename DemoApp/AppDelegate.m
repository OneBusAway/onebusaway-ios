//
//  AppDelegate.m
//  OBANetworking
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

#import "AppDelegate.h"
@import OBAKit;

#import "PermissionPromptViewController.h"

@interface AppDelegate ()<OBAApplicationDelegate, UITabBarControllerDelegate>
@property(nonatomic,strong) OBAApplication *app;
@property(nonatomic,strong) NSUserDefaults *userDefaults;
@property(nonatomic,strong) OBAClassicApplicationRootController *rootController;
@end

@implementation AppDelegate

- (instancetype)init {
    self = [super init];

    if (self) {
        NSURLCache *urlCache = [[NSURLCache alloc] initWithMemoryCapacity:4 * 1024 * 1024 diskCapacity:20 * 1024 * 1024 diskPath:nil];
        [NSURLCache setSharedURLCache:urlCache];

        _userDefaults = [NSUserDefaults standardUserDefaults];

        NSURL *regionsBaseURL = [NSURL URLWithString:@"http://regions.onebusaway.org"];
        OBAAppConfig *appConfig = [[OBAAppConfig alloc] initWithRegionsBaseURL:regionsBaseURL apiKey:@"test" uuid:NSUUID.UUID.UUIDString appVersion:@"1.0.test" userDefaults:_userDefaults];
        _app = [[OBAApplication alloc] initWithConfig:appConfig];
        _app.delegate = self;
    }

    return self;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    [self applicationReloadRootInterface:self.app];
    [self.window makeKeyAndVisible];

    return YES;
}

#pragma mark - OBAApplicationDelegate

- (void)setIdleTimerDisabled:(BOOL)idleTimerDisabled {
    UIApplication.sharedApplication.idleTimerDisabled = idleTimerDisabled;
}

- (BOOL)idleTimerDisabled {
    return UIApplication.sharedApplication.idleTimerDisabled;
}

- (void)applicationReloadRootInterface:(OBAApplication*)application {
    if (application.showPermissionPromptUI) {
        PermissionPromptViewController *promptViewController = [[PermissionPromptViewController alloc] initWithLocationService:application.locationService];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:promptViewController];
        self.window.rootViewController = nav;
    }
    else {
        self.rootController = [[OBAClassicApplicationRootController alloc] initWithApplication:application];
        self.rootController.selectedIndex = self.app.userDataStore.lastSelectedView;
        self.rootController.delegate = self;
        self.window.rootViewController = self.rootController;
    }
}

- (void)application:(OBAApplication *)app displayRegionPicker:(OBARegionPickerViewController *)picker {
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:picker];
}

- (BOOL)canOpenURL:(NSURL*)url {
    return [UIApplication.sharedApplication canOpenURL:url];
}

- (void)open:(NSURL * _Nonnull)url options:(NSDictionary<UIApplicationOpenExternalURLOptionsKey,id> * _Nonnull)options completionHandler:(void (^ _Nullable)(BOOL))completion {
    [UIApplication.sharedApplication openURL:url options:options completionHandler:completion];
}

#pragma mark - UITabBarControllerDelegate

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController {
    NSInteger index = tabBarController.selectedIndex;

    if (index == OBASelectedTabMap) {
        [self.rootController.mapController centerMapOnUserLocation];
    }

    self.app.userDataStore.lastSelectedView = (OBASelectedTab)index;
}

@end
