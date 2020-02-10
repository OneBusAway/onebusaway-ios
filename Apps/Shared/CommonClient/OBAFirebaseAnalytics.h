//
//  OBAFirebaseAnalytics.h
//  App
//
//  Created by Aaron Brethorst on 2/9/20.
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
