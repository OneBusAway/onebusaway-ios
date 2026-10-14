//
//  AppDelegate.m
//  OBANetworking
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "AppDelegate.h"
#import "SceneDelegate.h"
#import "OBARootInterfaceLauncher.h"
@import OBAKitCore;
@import OBAKit;

@interface AppDelegate ()<OBAApplicationDelegate>
@property(nonatomic,strong) NSUserDefaults *userDefaults;
@property(nonatomic,strong) UIViewController *rootController;
@end

@implementation AppDelegate

- (instancetype)init {
    self = [super init];

    if (self) {
        NSURLCache *urlCache = [[NSURLCache alloc] initWithMemoryCapacity:4 * 1024 * 1024 diskCapacity:20 * 1024 * 1024 diskPath:nil];
        [NSURLCache setSharedURLCache:urlCache];

        NSString *appGroup = NSBundle.mainBundle.appGroup;
        assert(appGroup);

        _userDefaults = [[NSUserDefaults alloc] initWithSuiteName:appGroup];
        [_userDefaults registerDefaults:@{
            OBAAnalyticsKeys.reportingEnabledUserDefaultsKey: @(YES)
        }];

        OBAAppConfig *appConfig = [[OBAAppConfig alloc] initWithAppBundle:NSBundle.mainBundle userDefaults:_userDefaults analytics:nil];

        _app = [[OBAApplication alloc] initWithConfig:appConfig];
        _app.delegate = self;
    }

    return self;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // The window, root interface, and active/resign lifecycle now live in
    // SceneDelegate, which forwards these launch options to the app stack.
    self.launchOptions = launchOptions;

    return YES;
}

#pragma mark - OBAApplicationDelegate

- (UIApplication*)uiApplication {
    return [UIApplication sharedApplication];
}

- (void)performTestCrash {
  // nop
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
    BOOL reloadedAnyScene = NO;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            UIWindow *window = nil;
            if ([windowScene.delegate isKindOfClass:[SceneDelegate class]]) {
                window = ((SceneDelegate *)windowScene.delegate).window;
            }
            if (!window) {
                window = windowScene.windows.firstObject;
            }
            if (window) {
                reloadedAnyScene = YES;
                [OBARootInterfaceLauncher reloadRootInterfaceWithApplication:application window:window showRootController:^{
                    UIViewController *controller = [OBAApplicationRootControllerFactory makeWithApplication:application];
                    window.rootViewController = controller;
                    if (window == self.window) {
                        self.rootController = controller;
                    }
                }];
            }
        }
    }

    if (!reloadedAnyScene && self.window) {
        [OBARootInterfaceLauncher reloadRootInterfaceWithApplication:application window:self.window showRootController:^{
            self.rootController = [OBAApplicationRootControllerFactory makeWithApplication:application];
            self.window.rootViewController = self.rootController;
        }];
    }
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
  return NO;
}

@end
