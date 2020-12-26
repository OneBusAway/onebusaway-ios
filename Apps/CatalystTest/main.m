//
//  main.m
//  OBANetworking
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
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

