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
    // Evaluates onboarding for the specified window and displays the root controller when ready.
    [OBAOnboardingFlowController evaluateWithApplication:application completion:^(OBAOnboardingFlowController * _Nullable onboarding) {
        if (onboarding) {
            onboarding.onFinished = ^{
                // The hierarchy change belongs inside the animations block so the
                // transition captures the correct before/after snapshots.
                [UIView transitionWithView:window duration:0.5 options:UIViewAnimationOptionTransitionFlipFromLeft animations:^{
                    showRootController();
                } completion:^(BOOL finished) {
                    [application rootUserInterfaceDidLoad];
                }];
            };
            window.rootViewController = onboarding;
        } else {
            showRootController();
            [application rootUserInterfaceDidLoad];
        }
    }];
}

@end
