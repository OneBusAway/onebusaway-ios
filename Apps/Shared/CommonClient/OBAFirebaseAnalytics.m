//
//  OBAFirebaseAnalytics.m
//  App
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "OBAFirebaseAnalytics.h"
#import <FirebaseCore/FirebaseCore.h>
#import <FirebaseAnalytics/FirebaseAnalytics.h>
#import <FirebaseCrashlytics/FirebaseCrashlytics.h>
@import OBAKitCore;

@interface OBAFirebaseAnalytics ()
@property(nonatomic,strong) NSUserDefaults *userDefaults;
@end

@implementation OBAFirebaseAnalytics

- (instancetype)initWithUserDefaults:(NSUserDefaults*)userDefaults {
    self = [super init];

    if (self) {
        _userDefaults = userDefaults;
    }
    return self;
}

- (void)configureWithUserID:(NSString*)userID {
    [FIRApp configure];
    [FIRAnalytics setUserID:userID];
}

#pragma mark - OBAAnalytics

- (BOOL)reportingEnabled {
    return [self.userDefaults boolForKey:OBAAnalyticsKeys.reportingEnabledUserDefaultsKey];
}

- (void)setReportingEnabled:(BOOL)enabled {
    [self.userDefaults setBool:enabled forKey:OBAAnalyticsKeys.reportingEnabledUserDefaultsKey];
    [FIRAnalytics setAnalyticsCollectionEnabled:enabled];
}

- (void)logEventWithName:(NSString *)name parameters:(NSDictionary<NSString *,id> *)parameters {
    [FIRAnalytics logEventWithName:name parameters:parameters];
}

- (void)reportEvent:(enum OBAAnalyticsEvent)event label:(NSString *)label value:(id)value {
    NSString *eventName = nil;

    if (event == OBAAnalyticsEventUserAction) {
        eventName = kFIRParameterContentType;
    }
    else {
        [OBALogger error:[NSString stringWithFormat:@"Invalid call to -reportEventWithCategory: %@ label: %@ value: %@", @(event), label, value]];
        return;
    }

    NSMutableDictionary *parameters = [[NSMutableDictionary alloc] init];
    parameters[kFIRParameterItemID] = label;

    if (value) {
        parameters[kFIRParameterItemVariant] = value;
    }

    [self logEventWithName:eventName parameters:parameters];
}

- (void)reportSearchQuery:(NSString*)searchQuery {
    [FIRAnalytics logEventWithName:kFIREventSearch parameters:@{kFIRParameterSearchTerm: searchQuery}];
}

- (void)reportStopViewedWithName:(NSString *)name id:(NSString *)id stopDistance:(NSString *)stopDistance {
    [self logEventWithName:kFIREventViewItem parameters:@{
        kFIRParameterItemID: id,
        kFIRParameterItemName: name,
        kFIRParameterItemCategory: @"stops",
        kFIRParameterItemLocationID: stopDistance
    }];
}

- (void)reportSetRegion:(NSString *)name {
    [self setUserPropertyWithKey:@"RegionName" value:name];
}

- (void)setUserPropertyWithKey:(NSString *)key value:(NSString *)value {
    [FIRAnalytics setUserPropertyString:value forName:key];
}


@end
