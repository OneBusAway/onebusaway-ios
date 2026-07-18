//
//  OBARootInterfaceLauncher.m
//  OBANetworking
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "OBARootInterfaceLauncher.h"
@import OBAKit;
@import OBAKitCore;

@implementation OBARootInterfaceLauncher

+ (void)reloadRootInterfaceWithApplication:(OBAApplication *)application
                                    window:(UIWindow *)window
                        showRootController:(void(^)(void))showRootController {
    // Assumes one invocation per launch (the only caller is applicationReloadRootInterface:).
    // A second in-flight call would race on window.rootViewController.
    [OBAOnboardingFlowController evaluateWithApplication:application completion:^(OBAOnboardingFlowController * _Nullable onboarding) {
        if (onboarding) {
            onboarding.onFinished = ^{
                showRootController();
                [UIView transitionWithView:window duration:0.5 options:UIViewAnimationOptionTransitionFlipFromLeft animations:nil completion:nil];
            };
            window.rootViewController = onboarding;
        } else {
            showRootController();
        }
    }];
}

@end
