//
//  OBARESTAPIOperation.h
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/3/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

@import Foundation;
#import <OBANetworkingKit/OBANetworkOperation.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(RESTAPIOperation)
@interface OBARESTAPIOperation : OBANetworkOperation

@property(nonatomic,strong,nullable,readonly) NSArray<NSDictionary<NSString*,id>*> *entries;
@property(nonatomic,strong,nullable,readonly) NSDictionary *references;

@end

NS_ASSUME_NONNULL_END
