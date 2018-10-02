//
//  OBANetworkOperation.m
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

#import <OBANetworkingKit/OBANetworkOperation.h>
#import <OBANetworkingKit/OBAOperation+Internal.h>

@interface OBANetworkOperation ()
@property(nonatomic,copy) NSURL *URL;
@property(nonatomic,strong,nullable,readwrite) NSData *data;
@property(nonatomic,copy,nullable,readwrite) NSError *error;
@property(nonatomic,strong,nullable,readwrite) NSHTTPURLResponse *response;
@property(nonatomic,strong,nullable) NSURLSessionDataTask *dataTask;
@end

@implementation OBANetworkOperation

- (instancetype)initWithURL:(NSURL*)URL {
    self = [super init];

    if (self) {
        _URL = [URL copy];
        self.name = _URL.absoluteString;
    }
    return self;
}

- (void)start {
    [super start];

    NSURLSession *session = [NSURLSession sharedSession];

    __weak __typeof__(self) weakSelf = self;
    self.dataTask = [session dataTaskWithRequest:[self URLRequest] completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        __typeof__(self) self = weakSelf;

        if (self.isCancelled) {
            return;
        }

        self.data = data;
        self.response = (NSHTTPURLResponse*)response;
        self.error = error;

        [self finish];
    }];

    [self.dataTask resume];
}

- (NSURLRequest*)URLRequest {
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:self.URL cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10.0];
    return request;
}

#pragma mark - Cancel

- (void)cancel {
    [super cancel];
    [self finish];
}

@end
