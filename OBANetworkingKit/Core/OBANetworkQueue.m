//
//  OBANetworkQueue.m
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

#import <OBANetworkingKit/OBANetworkQueue.h>
#import <OBANetworkingKit/OBAOperation.h>

@interface OBANetworkQueue ()
@property(nonatomic,strong) NSOperationQueue *operationQueue;
@end

@implementation OBANetworkQueue

- (instancetype)init {
    self = [super init];
    if (self) {
        _operationQueue = [[NSOperationQueue alloc] init];
    }
    return self;
}

- (void)addOperation:(OBAOperation *)operation {
    [self.operationQueue addOperation:operation];
}

- (void)cancelAllOperations {
    [self.operationQueue cancelAllOperations];
}

@end
