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
@import CocoaLumberjack;
@import Crashlytics;
#import "OBAFirebaseAnalytics.h"

@interface AppDelegate ()<OBAApplicationDelegate, OBAAnalytics>
@property(nonatomic,strong) OBAApplication *app;
@property(nonatomic,strong) NSUserDefaults *userDefaults;
@property(nonatomic,strong) OBAClassicApplicationRootController *rootController;
@property(nonatomic,strong) OBAFirebaseAnalytics *analyticsClient;
@end

@implementation AppDelegate

- (instancetype)init {
    self = [super init];

    if (self) {
        NSURLCache *urlCache = [[NSURLCache alloc] initWithMemoryCapacity:4 * 1024 * 1024 diskCapacity:20 * 1024 * 1024 diskPath:nil];
        [NSURLCache setSharedURLCache:urlCache];

        _userDefaults = [[NSUserDefaults alloc] initWithSuiteName:NSBundle.mainBundle.appGroup];
        [_userDefaults registerDefaults:@{
            OBAAnalyticsKeys.reportingEnabledUserDefaultsKey: @(YES)
        }];

        _analyticsClient = [[OBAFirebaseAnalytics alloc] initWithUserDefaults:_userDefaults];

        OBAAppConfig *appConfig = [[OBAAppConfig alloc] initWithAppBundle:NSBundle.mainBundle userDefaults:_userDefaults analytics:_analyticsClient];

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

    [self.analyticsClient configureWithUserID:self.app.userUUID];

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
    self.window.rootViewController = self.rootController;
}

- (BOOL)canOpenURL:(NSURL*)url {
    return [UIApplication.sharedApplication canOpenURL:url];
}

- (void)open:(NSURL * _Nonnull)url options:(NSDictionary<UIApplicationOpenExternalURLOptionsKey,id> * _Nonnull)options completionHandler:(void (^ _Nullable)(BOOL))completion {
    [UIApplication.sharedApplication openURL:url options:options completionHandler:completion];
}

- (NSDictionary<NSString*, NSString*>*)credits {
    return @{@"Firebase": @"https://raw.githubusercontent.com/firebase/firebase-ios-sdk/master/LICENSE"};
}

#pragma mark - Push Notifications

- (BOOL)isRegisteredForRemoteNotifications {
    // return [OneSignal getPermissionSubscriptionState].permissionStatus.status == OSNotificationPermissionAuthorized;
    return NO;
}

@end
