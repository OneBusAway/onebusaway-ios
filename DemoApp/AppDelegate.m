//
//  AppDelegate.m
//  OBANetworking
//
//  Created by Aaron Brethorst on 10/2/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

#import "AppDelegate.h"
@import OBAKit;

#import "DemoViewController.h"
#import "PermissionPromptViewController.h"

@interface AppDelegate ()<OBAApplicationDelegate>
@property(nonatomic,strong) OBAApplication *app;
@property(nonatomic,strong) NSUserDefaults *userDefaults;
@property(nonatomic,strong) OBAClassicApplicationRootController *rootController;
@end

@implementation AppDelegate

- (instancetype)init {
    self = [super init];

    if (self) {
        NSURLCache *urlCache = [[NSURLCache alloc] initWithMemoryCapacity:4 * 1024 * 1024 diskCapacity:20 * 1024 * 1024 diskPath:nil];
        [NSURLCache setSharedURLCache:urlCache];

        _userDefaults = [NSUserDefaults standardUserDefaults];

        NSURL *regionsBaseURL = [NSURL URLWithString:@"http://regions.onebusaway.org"];
        OBAAppConfig *appConfig = [[OBAAppConfig alloc] initWithRegionsBaseURL:regionsBaseURL apiKey:@"test" uuid:NSUUID.UUID.UUIDString appVersion:@"1.0.test" userDefaults:_userDefaults];
        _app = [[OBAApplication alloc] initWithConfig:appConfig];
        _app.delegate = self;
        [_app configureAppearanceProxies];
    }

    return self;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    [self applicationReloadRootInterface:self.app];
    [self.window makeKeyAndVisible];

    return YES;
}

#pragma mark - OBAApplicationDelegate

- (void)applicationReloadRootInterface:(OBAApplication*)application {
//    func applicationReloadRootInterface(_ app: Application) {
//        if app.showPermissionPromptUI {
//            let permissionPromptController = PermissionPromptViewController(application: app)
//            let navigation = UINavigationController(rootViewController: permissionPromptController)
//            window?.rootViewController = navigation
//        }
//        else {
//            let controller = ClassicApplicationRootController(application: app)
//            window?.rootViewController = controller
//        }
//    }
    if (application.showPermissionPromptUI) {
        PermissionPromptViewController *promptViewController = [[PermissionPromptViewController alloc] initWithLocationService:application.locationService];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:promptViewController];
        self.window.rootViewController = nav;
    }
    else {
        self.rootController = [[OBAClassicApplicationRootController alloc] initWithApplication:application];
        self.window.rootViewController = self.rootController;
    }
}

- (void)application:(OBAApplication *)app displayRegionPicker:(OBARegionPickerViewController *)picker {
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:picker];
}

@end
