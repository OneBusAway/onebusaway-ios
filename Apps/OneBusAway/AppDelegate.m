//
//  AppDelegate.m
//  OBANetworking
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

#import "AppDelegate.h"
@import OBAKitCore;
@import OBAKit;
#import "Firebase.h"
@import Crashlytics;
@import OneSignal;

@interface AppDelegate ()<OBAApplicationDelegate, UITabBarControllerDelegate, OBAAnalytics>
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

        OBAAppConfig *appConfig = [[OBAAppConfig alloc] initWithAppBundle:NSBundle.mainBundle userDefaults:_userDefaults analytics:self];

        NSString *pushKey = NSBundle.mainBundle.infoDictionary[@"OBAKitConfig"][@"PushNotificationAPIKey"];
        OBAOneSignalPushService *pushService = [[OBAOneSignalPushService alloc] initWithAPIKey:pushKey];
        appConfig.pushServiceProvider = pushService;

        _app = [[OBAApplication alloc] initWithConfig:appConfig];
        _app.delegate = self;
    }

    return self;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    [self.app application:application didFinishLaunching:launchOptions];

    [self applicationReloadRootInterface:self.app];
    [self.window makeKeyAndVisible];

    [FIRApp configure];

    return YES;
}

#pragma mark - OBAApplicationDelegate

- (UIApplication*)uiApplication {
    return [UIApplication sharedApplication];
}

- (void)performTestCrash {
    [Crashlytics.sharedInstance crash];
}

- (void)setIdleTimerDisabled:(BOOL)idleTimerDisabled {
    UIApplication.sharedApplication.idleTimerDisabled = idleTimerDisabled;
}

- (BOOL)idleTimerDisabled {
    return UIApplication.sharedApplication.idleTimerDisabled;
}

- (BOOL)registeredForRemoteNotifications {
    return UIApplication.sharedApplication.registeredForRemoteNotifications;
}

- (void)applicationReloadRootInterface:(OBAApplication*)application {
    if (application.showPermissionPromptUI) {
        OBAPermissionPromptViewController *promptViewController = [[OBAPermissionPromptViewController alloc] initWithApplication:application];
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
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:picker];
    nav.navigationBar.prefersLargeTitles = NO;
    self.window.rootViewController = nav;
}

- (BOOL)canOpenURL:(NSURL*)url {
    return [UIApplication.sharedApplication canOpenURL:url];
}

- (void)open:(NSURL * _Nonnull)url options:(NSDictionary<UIApplicationOpenExternalURLOptionsKey,id> * _Nonnull)options completionHandler:(void (^ _Nullable)(BOOL))completion {
    [UIApplication.sharedApplication openURL:url options:options completionHandler:completion];
}

- (NSDictionary<NSString*, NSString*>*)credits {
    return @{@"Firebase": @"Contains the Google Firebase SDK, whose license can be found here: https://raw.githubusercontent.com/firebase/firebase-ios-sdk/master/LICENSE"};
}

#pragma mark - UITabBarControllerDelegate

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController {
    NSInteger index = tabBarController.selectedIndex;

    if (index == OBASelectedTabMap) {
        [self.rootController.mapController centerMapOnUserLocation];
    }

    self.app.userDataStore.lastSelectedView = (OBASelectedTab)index;
}

#pragma mark - OBAAnalytics

- (void)logEventWithName:(NSString *)name parameters:(NSDictionary<NSString *,id> *)parameters {
    // abxoxo - TODO!
}

- (void)reportEventWithCategory:(enum OBAAnalyticsCategory)category action:(NSString *)action label:(NSString *)label value:(id)value {
    // abxoxo - TODO!
}

#pragma mark - Push Notifications

- (BOOL)isRegisteredForRemoteNotifications {
    return [OneSignal getPermissionSubscriptionState].permissionStatus.status == OSNotificationPermissionAuthorized;
}


@end
