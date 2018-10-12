//
//  OBANetworkHelpers.h
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(NetworkHelpers)
@interface OBANetworkHelpers : NSObject

+ (NSArray<NSURLQueryItem*>*)dictionaryToQueryItems:(nullable NSDictionary*)dictionary;
+ (NSString*)escapePathVariable:(NSString*)pathVariable;
+ (NSData*)dictionaryToHTTPBodyData:(NSDictionary*)dictionary;

@end

NS_ASSUME_NONNULL_END
