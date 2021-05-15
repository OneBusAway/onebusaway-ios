//
//  OBAFirebaseAnalytics.h
//  App
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

@import Foundation;
@import OBAKitCore;
@import OBAKit;

NS_ASSUME_NONNULL_BEGIN

@interface OBAFirebaseAnalytics : NSObject<OBAAnalytics>
- (instancetype)initWithUserDefaults:(NSUserDefaults*)userDefaults;

- (void)configureWithUserID:(NSString*)userID;

@end

NS_ASSUME_NONNULL_END
