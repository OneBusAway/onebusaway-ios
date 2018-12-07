//
//  OBARESTAPIOperation.h
//  OBAKit
//
//  Created by Aaron Brethorst on 10/3/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

@import Foundation;
#import <OBAKit/OBANetworkOperation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The core API operation class for the OBA REST API.

 Important: An `error` with Domain=NSCocoaErrorDomain, Code=3840 usually means that you're hitting a captive portal.
 */
NS_SWIFT_NAME(RESTAPIOperation) @interface OBARESTAPIOperation : OBANetworkOperation

@property(nonatomic,strong,nullable,readonly) NSArray<NSDictionary<NSString*,id>*> *entries;
@property(nonatomic,strong,nullable,readonly) NSDictionary<NSString*,id> *references;

@end

NS_ASSUME_NONNULL_END
