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

@end

NS_ASSUME_NONNULL_END
