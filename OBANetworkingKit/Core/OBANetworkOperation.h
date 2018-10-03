//
//  OBANetworkOperation.h
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

#import <OBANetworkingKit/OBAOperation.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(NetworkOperation)
@interface OBANetworkOperation : OBAOperation
@property(nonatomic,strong,nullable,readonly) NSData *data;
@property(nonatomic,copy,nullable,readonly) NSError *error;
@property(nonatomic,strong,nullable,readonly) NSHTTPURLResponse *response;

- (instancetype)initWithURL:(NSURL*)URL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSURLRequest*)URLRequest;

/**
 Constructs the URL for this network operation given a base URL and an optional
 dictionary of query params.

 @note Subclasses *must* override this method. Calling -super is unnecessary.

 @param URL The Region's API base URL
 @param params An optional dictionary of query params
 @return The URL for this operation's API endpoint
 */
+ (NSURL*)buildURLWithBaseURL:(NSURL*)URL params:(nullable NSDictionary*)params;

@end

NS_ASSUME_NONNULL_END
