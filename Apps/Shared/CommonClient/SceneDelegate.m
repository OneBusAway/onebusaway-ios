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
#import "OBARootInterfaceLauncher.h"
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

    OBAApplication *app = appDelegate.app;

    if (!appDelegate.hasFinishedLaunching) {
        appDelegate.hasFinishedLaunching = YES;
        // Hand the initial scene's window to the app delegate so that single-window
        // fallbacks and legacy references continue to work.
        appDelegate.window = self.window;

        // This builds the application's UI by calling back into -applicationReloadRootInterface:,
        // which attaches the root view controller to the window created above.
        [app application:UIApplication.sharedApplication didFinishLaunching:appDelegate.launchOptions];
    } else {
        // The application stack has already launched (e.g. secondary scene on iPad).
        // Directly initialize the root interface for this window.
        [OBARootInterfaceLauncher reloadRootInterfaceWithApplication:app window:self.window showRootController:^{
            self.window.rootViewController = [OBAApplicationRootControllerFactory makeWithApplication:app];
        }];
    }

    // Handle any URLs or user activities this scene was launched to handle.
    for (UIOpenURLContext *context in connectionOptions.URLContexts) {
        (void)[app application:UIApplication.sharedApplication open:context.URL options:@{}];
    }

    for (NSUserActivity *activity in connectionOptions.userActivities) {
        (void)[app application:UIApplication.sharedApplication continue:activity restorationHandler:^(NSArray<id<UIUserActivityRestoring>> * _Nullable restorableObjects) {}];
    }

    // Restore state from a preserved session user activity if no connection activities were passed.
    if (connectionOptions.userActivities.count == 0 && session.stateRestorationActivity != nil) {
        (void)[app application:UIApplication.sharedApplication continue:session.stateRestorationActivity restorationHandler:^(NSArray<id<UIUserActivityRestoring>> * _Nullable restorableObjects) {}];
    }
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    AppDelegate *appDelegate = (AppDelegate *)UIApplication.sharedApplication.delegate;
    if ([appDelegate isKindOfClass:[AppDelegate class]] && appDelegate.window == self.window) {
        // If the disconnected scene's window was tracked by appDelegate.window,
        // point appDelegate.window to another connected window if available.
        UIWindow *fallbackWindow = nil;
        for (UIScene *connectedScene in UIApplication.sharedApplication.connectedScenes) {
            if (connectedScene != scene && [connectedScene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)connectedScene;
                if ([windowScene.delegate isKindOfClass:[SceneDelegate class]]) {
                    fallbackWindow = ((SceneDelegate *)windowScene.delegate).window;
                    if (fallbackWindow) {
                        break;
                    }
                }
            }
        }
        appDelegate.window = fallbackWindow;
    }
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    // Only trigger application-level activation when this is the first scene to
    // become active; skip if another scene is already in the foreground-active state.
    for (UIScene *connectedScene in UIApplication.sharedApplication.connectedScenes) {
        if (connectedScene != scene && connectedScene.activationState == UISceneActivationStateForegroundActive) {
            return;
        }
    }
    [[self obaApplication] applicationDidBecomeActive:UIApplication.sharedApplication];
}

- (void)sceneWillResignActive:(UIScene *)scene {
    // Only resign active for the application if no other connected scenes remain active.
    for (UIScene *connectedScene in UIApplication.sharedApplication.connectedScenes) {
        if (connectedScene != scene && connectedScene.activationState == UISceneActivationStateForegroundActive) {
            return;
        }
    }
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

- (NSUserActivity *)userActivityForViewController:(UIViewController *)viewController {
    if (!viewController) {
        return nil;
    }

    if (viewController.presentedViewController) {
        NSUserActivity *activity = [self userActivityForViewController:viewController.presentedViewController];
        if (activity) {
            return activity;
        }
    }

    if ([viewController isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabBar = (UITabBarController *)viewController;
        NSUserActivity *activity = [self userActivityForViewController:tabBar.selectedViewController];
        if (activity) {
            return activity;
        }
    }

    if ([viewController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)viewController;
        for (UIViewController *child in nav.viewControllers.reverseObjectEnumerator) {
            NSUserActivity *activity = [self userActivityForViewController:child];
            if (activity) {
                return activity;
            }
        }
    }

    return viewController.userActivity;
}

- (NSUserActivity *)stateRestorationActivityForScene:(UIScene *)scene {
    return [self userActivityForViewController:self.window.rootViewController];
}

@end
