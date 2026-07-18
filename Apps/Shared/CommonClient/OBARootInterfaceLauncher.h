//
//  OBARootInterfaceLauncher.h
//  OBANetworking
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#import <UIKit/UIKit.h>

@class OBAApplication;

NS_ASSUME_NONNULL_BEGIN

/// Shared launch glue for all white-label apps: evaluates the onboarding flow and either
/// installs it as the window's root (handing off to `showRootController` when the user
/// finishes) or calls `showRootController` immediately when no onboarding is needed.
NS_SWIFT_UI_ACTOR
@interface OBARootInterfaceLauncher : NSObject

+ (void)reloadRootInterfaceWithApplication:(OBAApplication *)application
                                    window:(UIWindow *)window
                        showRootController:(void(^)(void))showRootController;

@end

NS_ASSUME_NONNULL_END
