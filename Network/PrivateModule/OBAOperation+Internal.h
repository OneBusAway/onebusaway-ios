//
//  OBAOperation+Internal.h
//  OBAKit
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

#import <OBAKit/OBAOperation.h>
#import <OBAKit/OBANetworkOperation.h>
#import <OBAKit/OBARESTAPIOperation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OBAOperation (Internal)
- (void)finish;
@end

@interface OBANetworkOperation (Internal)
- (void)setData:(NSData*)data response:(NSHTTPURLResponse*)response error:(NSError*)error;
@property(nonatomic,copy,nullable,readwrite) NSError *error;
@property(nonatomic,strong,nullable,readwrite) NSHTTPURLResponse *response;

+ (NSURL*)_buildURLFromBaseURL:(NSURL*)URL path:(NSString*)path queryItems:(NSArray<NSURLQueryItem*>*)queryItems;
@end

@interface OBARESTAPIOperation (Internal)
/**
 The full JSON body decoded from `data`. Only available after `-setData:response:error:` is called.
 */
@property(nonatomic,strong,nullable,readonly) id _decodedJSONBody;

- (void)_dataFieldsDidSet;

@end

NS_ASSUME_NONNULL_END
