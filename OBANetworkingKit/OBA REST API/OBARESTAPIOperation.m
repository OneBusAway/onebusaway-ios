//
//  OBARESTAPIOperation.m
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/3/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

#import <OBANetworkingKit/OBARESTAPIOperation.h>
#import <OBANetworkingKit/OBAOperation+Internal.h>

@interface OBARESTAPIOperation ()
@property(nonatomic,strong,nullable,readwrite) NSArray<NSDictionary*> *entries;
@property(nonatomic,strong,nullable,readwrite) NSDictionary *references;
@property(nonatomic,strong,nullable,readwrite) id _decodedJSONBody;
@end

@implementation OBARESTAPIOperation

- (void)setData:(NSData *)data response:(NSHTTPURLResponse *)response error:(NSError *)error {
    [super setData:data response:response error:error];

    if (!data) {
        return;
    }

    NSError *jsonError = nil;
    self._decodedJSONBody = [NSJSONSerialization JSONObjectWithData:self.data options:0 error:&jsonError];

    if (jsonError) {
        self.error = jsonError;
        return;
    }

    if ([self._decodedJSONBody respondsToSelector:@selector(valueForKey:)]) {
        NSInteger statusCode = [[self._decodedJSONBody valueForKey:@"code"] integerValue];

        self.response = [[NSHTTPURLResponse alloc] initWithURL:self.response.URL statusCode:statusCode HTTPVersion:nil headerFields:self.response.allHeaderFields];

        NSDictionary *dataField = self._decodedJSONBody[@"data"];

        NSDictionary *entry = dataField[@"entry"];
        if (entry) {
            self.entries = @[entry];
        }
        else {
            self.entries = dataField[@"list"];
        }

        self.references = dataField[@"references"];
    }

    [self _dataFieldsDidSet];
}

- (void)_dataFieldsDidSet {
    // nop
}

@end
