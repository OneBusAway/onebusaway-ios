//
//  OBANetworkOperation.h
//  OBAKit
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

#import <OBAKit/OBAOperation.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(NetworkOperation)
@interface OBANetworkOperation : OBAOperation
@property(nonatomic,copy,readonly) NSURLRequest *request;
@property(nonatomic,strong,nullable,readonly) NSData *data;
@property(nonatomic,strong,nullable,readonly) NSHTTPURLResponse *response;
@property(nonatomic,assign,readonly) BOOL success;

- (instancetype)initWithURLRequest:(NSURLRequest*)request NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithURL:(NSURL*)URL;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
