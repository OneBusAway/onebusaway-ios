//
//  SceneDelegate.m
//  OBANetworking
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "SceneDelegate.h"
#import "AppDelegate.h"
@import OBAKit;
@import OBAKitCore;

@implementation SceneDelegate

// The real `AppDelegate` owns the `OBAApplication` stack. When running unit
// tests, the host uses a bare `TestAppDelegate`, so this returns nil and the
// scene simply provides an empty window.
- (OBAApplication *)obaApplication {
    id<UIApplicationDelegate> delegate = UIApplication.sharedApplication.delegate;
    if ([delegate isKindOfClass:[AppDelegate class]]) {
        return ((AppDelegate *)delegate).app;
    }
    return nil;
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }

    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    [self.window makeKeyAndVisible];

    AppDelegate *appDelegate = (AppDelegate *)UIApplication.sharedApplication.delegate;
    if (![appDelegate isKindOfClass:[AppDelegate class]]) {
        // Unit test host: no application stack to attach.
        return;
    }

    // Hand the scene's window to the app delegate so that -applicationReloadRootInterface:
    // (which can be called at any time in response to region/permission changes) has a
    // window to attach the root view controller to.
    appDelegate.window = self.window;

    OBAApplication *app = appDelegate.app;

    // This builds the application's UI by calling back into -applicationReloadRootInterface:,
    // which attaches the root view controller to the window created above.
    [app application:UIApplication.sharedApplication didFinishLaunching:appDelegate.launchOptions];

    // Handle any URLs or user activities the app was launched to handle.
    for (UIOpenURLContext *context in connectionOptions.URLContexts) {
        (void)[app application:UIApplication.sharedApplication open:context.URL options:@{}];
    }

    for (NSUserActivity *activity in connectionOptions.userActivities) {
        (void)[app application:UIApplication.sharedApplication continue:activity restorationHandler:^(NSArray<id<UIUserActivityRestoring>> * _Nullable restorableObjects) {}];
    }
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    [[self obaApplication] applicationDidBecomeActive:UIApplication.sharedApplication];
}

- (void)sceneWillResignActive:(UIScene *)scene {
    [[self obaApplication] applicationWillResignActive:UIApplication.sharedApplication];
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    OBAApplication *app = [self obaApplication];
    for (UIOpenURLContext *context in URLContexts) {
        (void)[app application:UIApplication.sharedApplication open:context.URL options:@{}];
    }
}

- (void)scene:(UIScene *)scene continueUserActivity:(NSUserActivity *)userActivity {
    (void)[[self obaApplication] application:UIApplication.sharedApplication continue:userActivity restorationHandler:^(NSArray<id<UIUserActivityRestoring>> * _Nullable restorableObjects) {}];
}

@end
