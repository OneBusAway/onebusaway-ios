//
//  OBAWrappedResponseNetworkOperation.h
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/3/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

@import Foundation;
#import <OBANetworkingKit/OBANetworkOperation.h>

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(WrappedResponseNetworkOperation)
@interface OBAWrappedResponseNetworkOperation : OBANetworkOperation

@property(nonatomic,strong,nullable,readonly) id entry;
@property(nonatomic,strong,nullable,readonly) id references;

@end

NS_ASSUME_NONNULL_END
