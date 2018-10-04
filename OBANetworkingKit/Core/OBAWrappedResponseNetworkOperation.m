//
//  OBAWrappedResponseNetworkOperation.m
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/3/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

#import <OBANetworkingKit/OBAWrappedResponseNetworkOperation.h>
#import <OBANetworkingKit/OBAOperation+Internal.h>

@interface OBAWrappedResponseNetworkOperation ()
@property(nonatomic,strong,nullable,readwrite) NSArray<NSDictionary*> *entries;
@property(nonatomic,strong,nullable,readwrite) NSDictionary *references;
@end

@implementation OBAWrappedResponseNetworkOperation

- (void)setData:(NSData *)data response:(NSHTTPURLResponse *)response error:(NSError *)error {
    [super setData:data response:response error:error];

    if (!data) {
        return;
    }

    NSError *jsonError = nil;
    id decodedBody = [NSJSONSerialization JSONObjectWithData:self.data options:0 error:&jsonError];

    if (jsonError) {
        self.error = jsonError;
        return;
    }

    if ([decodedBody respondsToSelector:@selector(valueForKey:)]) {
        NSInteger statusCode = [[decodedBody valueForKey:@"code"] integerValue];

        self.response = [[NSHTTPURLResponse alloc] initWithURL:self.response.URL statusCode:statusCode HTTPVersion:nil headerFields:self.response.allHeaderFields];

        NSDictionary *dataField = decodedBody[@"data"];

        NSDictionary *entry = dataField[@"entry"];
        if (entry) {
            self.entries = @[entry];
        }
        else {
            self.entries = dataField[@"list"];
        }

        self.references = dataField[@"references"];
    }
}

@end
