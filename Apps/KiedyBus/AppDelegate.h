//
//  AppDelegate.h
//  OBANetworking
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#import <UIKit/UIKit.h>

@class OBAApplication;

/// NS_SWIFT_UI_ACTOR: the app delegate is main-thread-bound by UIKit contract;
/// this lets Swift (in the Swift 6 language mode) call its properties without
/// isolation errors.
NS_SWIFT_UI_ACTOR
@interface AppDelegate : UIResponder <UIApplicationDelegate>

/// Set by the `SceneDelegate` once its window is created. The root view
/// controller is attached to this window in -applicationReloadRootInterface:.
@property (weak, nonatomic) UIWindow *window;

/// The application stack. Created in -init and consumed by the `SceneDelegate`.
@property (strong, nonatomic) OBAApplication *app;

/// Launch options captured in -application:didFinishLaunchingWithOptions:, so the
/// `SceneDelegate` can forward them when it finishes launching the app.
@property (copy, nonatomic, nullable) NSDictionary *launchOptions;

@end

