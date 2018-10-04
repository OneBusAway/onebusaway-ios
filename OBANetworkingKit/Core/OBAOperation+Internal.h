//
//  OBAOperation+Internal.h
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

#import <OBANetworkingKit/OBAOperation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OBAOperation (Internal)

- (void)finish;

@end

@interface OBANetworkOperation (Internal)

- (void)setData:(NSData*)data response:(NSHTTPURLResponse*)response error:(NSError*)error;
@property(nonatomic,copy,nullable,readwrite) NSError *error;
@property(nonatomic,strong,nullable,readwrite) NSHTTPURLResponse *response;

@end

NS_ASSUME_NONNULL_END
