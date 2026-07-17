//
//  SceneDelegate.h
//  OBANetworking
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#import <UIKit/UIKit.h>

/// NS_SWIFT_UI_ACTOR: scene delegates are main-thread-bound by UIKit contract.
NS_SWIFT_UI_ACTOR
@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>

@property (strong, nonatomic) UIWindow *window;

@end
