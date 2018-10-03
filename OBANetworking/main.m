//
//  main.m
//  OBANetworking
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"

@interface TestAppDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation TestAppDelegate
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {

#if DEBUG
        NSLog(@"Bundle Path: %@", [NSBundle mainBundle].bundlePath);
#endif

        NSDictionary *processInfoEnv = [NSProcessInfo processInfo].environment;

        BOOL executingTests = [[processInfoEnv[@"XCInjectBundle"] pathExtension] isEqual:@"xctest"];
        if (!executingTests) {
            executingTests = !!processInfoEnv[@"XCInjectBundleInto"];
        }

        NSString *appDelegateClass = executingTests ? @"TestAppDelegate" : @"AppDelegate";

        int retVal = UIApplicationMain(argc, argv, nil, appDelegateClass);
        return retVal;
    }
}

