//
//  OBANetworkHelpers.m
//  OBANetworkingKit
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

#import <OBANetworkingKit/OBANetworkHelpers.h>

@implementation OBANetworkHelpers

+ (NSArray<NSURLQueryItem*>*)dictionaryToQueryItems:(nullable NSDictionary*)dictionary; {
    if (!dictionary) {
        return @[];
    }

    NSMutableArray<NSURLQueryItem*> *queryArgs = [[NSMutableArray alloc] init];

    for (NSString* key in dictionary) {
        NSURLQueryItem *item = [[NSURLQueryItem alloc] initWithName:key value:[dictionary[key] description]];
        [queryArgs addObject:item];
    }

    return [queryArgs copy];
}

@end
