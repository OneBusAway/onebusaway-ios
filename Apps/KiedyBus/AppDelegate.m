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
@import CocoaLumberjack;

static const int ddLogLevel = DDLogLevelWarning;

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
        [_userDefaults registerDefaults:@{
            OBAAnalyticsKeys.reportingEnabledUserDefaultsKey: @(YES)
        }];

        NSString *bundledRegions = [NSBundle.mainBundle pathForResource:@"regions" ofType:@"json"];
        OBAAppConfig *appConfig = [[OBAAppConfig alloc] initWithAppBundle:NSBundle.mainBundle userDefaults:_userDefaults analytics:self bundledRegionsFilePath:bundledRegions];

        // Add a PushNotificationAPIKey to the Info.plist and then uncomment this to re-enable push.
        // NSString *pushKey = NSBundle.mainBundle.infoDictionary[@"OBAKitConfig"][@"PushNotificationAPIKey"];
        // OBAOneSignalPushService *pushService = [[OBAOneSignalPushService alloc] initWithAPIKey:pushKey];
        // appConfig.pushServiceProvider = pushService;

        _app = [[OBAApplication alloc] initWithConfig:appConfig];
        _app.delegate = self;
    }

    return self;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    [self.window makeKeyAndVisible];

    // This method will call -applicationReloadRootInterface:, which creates the
    // application's UI and attaches it to the window, so no need to do that here.
    [self.app application:application didFinishLaunching:launchOptions];

    [FIRApp configure];
    [FIRAnalytics setUserID:self.app.userUUID];

    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    [self.app applicationDidBecomeActive:application];
}

- (void)applicationWillResignActive:(UIApplication *)application {
    [self.app applicationWillResignActive:application];
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
    self.rootController = [[OBAClassicApplicationRootController alloc] initWithApplication:application];
    self.rootController.selectedIndex = self.app.userDataStore.lastSelectedView;
    self.rootController.delegate = self;
    self.window.rootViewController = self.rootController;
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

- (BOOL)tabBarController:(UITabBarController *)tabBarController shouldSelectViewController:(UIViewController *)viewController {
    // If the user is already on the map tab and they tap on the map tab item again, then zoom to their location.
    if (tabBarController.selectedViewController == viewController && tabBarController.selectedIndex == OBASelectedTabMap) {
        [self.rootController.mapController centerMapOnUserLocation];
    }

    return YES;
}

- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController {
    self.app.userDataStore.lastSelectedView = (OBASelectedTab)tabBarController.selectedIndex;
}

#pragma mark - OBAAnalytics

- (BOOL)reportingEnabled {
    return [self.userDefaults boolForKey:OBAAnalyticsKeys.reportingEnabledUserDefaultsKey];
}

- (void)setReportingEnabled:(BOOL)enabled {
    [self.userDefaults setBool:enabled forKey:OBAAnalyticsKeys.reportingEnabledUserDefaultsKey];
    [FIRAnalytics setAnalyticsCollectionEnabled:enabled];
}

- (void)logEventWithName:(NSString *)name parameters:(NSDictionary<NSString *,id> *)parameters {
    [FIRAnalytics logEventWithName:name parameters:parameters];
}

- (void)reportEvent:(enum OBAAnalyticsEvent)event label:(NSString *)label value:(id)value {
    NSString *eventName = nil;

    if (event == OBAAnalyticsEventUserAction) {
        eventName = kFIRParameterContentType;
    }
    else {
        DDLogError(@"Invalid call to -reportEventWithCategory: %@ label: %@ value: %@", @(event), label, value);
        return;
    }

    NSMutableDictionary *parameters = [[NSMutableDictionary alloc] init];
    parameters[kFIRParameterItemID] = label;

    if (value) {
        parameters[kFIRParameterItemVariant] = value;
    }

    [self logEventWithName:eventName parameters:parameters];
}

#pragma mark - Push Notifications

- (BOOL)isRegisteredForRemoteNotifications {
    return [OneSignal getPermissionSubscriptionState].permissionStatus.status == OSNotificationPermissionAuthorized;
}

@end
