//
//  OBANetworkQueue.h
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

@import Foundation;

@class OBAOperation;

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(NetworkQueue)
@interface OBANetworkQueue : NSObject

- (void)addOperation:(OBAOperation*)operation;
- (void)cancelAllOperations;

@end

NS_ASSUME_NONNULL_END
