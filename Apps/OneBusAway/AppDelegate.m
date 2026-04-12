//
//  AppDelegate.m
//  OBANetworking
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "AppDelegate.h"
@import OBAKitCore;
@import OBAKit;
#import <FirebaseCrashlytics/FirebaseCrashlytics.h>
#import "App-Swift.h"

@interface AppDelegate ()<OBAApplicationDelegate>
@property(nonatomic,strong) OBAApplication *app;
@property(nonatomic,strong) NSUserDefaults *userDefaults;
@property(nonatomic,strong) OBAClassicApplicationRootController *rootController;
@property(nonatomic,strong) OBAAnalyticsOrchestrator *analyticsClient;
@property(nonatomic,strong) OBACloudPushService *pushService;
@end

@implementation AppDelegate

- (instancetype)init {
    self = [super init];

    if (self) {
        NSURLCache *urlCache = [[NSURLCache alloc] initWithMemoryCapacity:4 * 1024 * 1024 diskCapacity:20 * 1024 * 1024 diskPath:nil];
        [NSURLCache setSharedURLCache:urlCache];

        NSString *appGroup = NSBundle.mainBundle.appGroup;
        assert(appGroup);

        _userDefaults = [[NSUserDefaults alloc] initWithSuiteName:appGroup];

        [_userDefaults registerDefaults:@{
            OBAAnalyticsKeys.reportingEnabledUserDefaultsKey: @(YES)
        }];

//        // If you need to debug a user's NSUserDefaults data, drop the XML file they provide into Xcode's Project Navigator
//        // with the name "userdefaults.xml". Then, uncomment this section.
//        NSData *data = [NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"userdefaults" ofType:@"xml"]];
//        NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:nil error:nil];
//        [_userDefaults registerDefaults:plist];

        _analyticsClient = [[OBAAnalyticsOrchestrator alloc] initWithUserDefaults:_userDefaults];

        OBAAppConfig *appConfig = [[OBAAppConfig alloc] initWithAppBundle:NSBundle.mainBundle userDefaults:_userDefaults analytics:_analyticsClient];

        _pushService = [[OBACloudPushService alloc] init];
        appConfig.pushServiceProvider = _pushService;

        _app = [[OBAApplication alloc] initWithConfig:appConfig];
        _app.delegate = self;
    }

    return self;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    UIColor *brandGreen = [UIColor colorWithRed:0x78/255.0 green:0xAA/255.0 blue:0x36/255.0 alpha:1.0];

    UIViewController *splashVC = [[UIViewController alloc] init];
    splashVC.view.backgroundColor = [UIColor systemBackgroundColor];

    UIImageView *logoView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"LaunchLogo"]];
    logoView.contentMode = UIViewContentModeScaleAspectFit;
    logoView.layer.cornerRadius = 28;
    logoView.layer.cornerCurve = kCACornerCurveContinuous;
    logoView.clipsToBounds = YES;
    logoView.translatesAutoresizingMaskIntoConstraints = NO;
    [splashVC.view addSubview:logoView];

    UILabel *nameLabel = [[UILabel alloc] init];
    nameLabel.text = @"OneBusAway";
    nameLabel.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];
    nameLabel.textColor = brandGreen;
    nameLabel.textAlignment = NSTextAlignmentCenter;
    nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [splashVC.view addSubview:nameLabel];

    UILabel *tagLabel = [[UILabel alloc] init];
    tagLabel.text = @"Public Transit";
    tagLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    tagLabel.textColor = [UIColor systemGrayColor];
    tagLabel.textAlignment = NSTextAlignmentCenter;
    tagLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [splashVC.view addSubview:tagLabel];

    [NSLayoutConstraint activateConstraints:@[
        [logoView.centerXAnchor constraintEqualToAnchor:splashVC.view.centerXAnchor],
        [logoView.centerYAnchor constraintEqualToAnchor:splashVC.view.centerYAnchor constant:-50],
        [logoView.widthAnchor constraintEqualToConstant:120],
        [logoView.heightAnchor constraintEqualToConstant:120],
        [nameLabel.topAnchor constraintEqualToAnchor:logoView.bottomAnchor constant:20],
        [nameLabel.centerXAnchor constraintEqualToAnchor:splashVC.view.centerXAnchor],
        [tagLabel.topAnchor constraintEqualToAnchor:nameLabel.bottomAnchor constant:6],
        [tagLabel.centerXAnchor constraintEqualToAnchor:splashVC.view.centerXAnchor],
    ]];

    splashVC.view.alpha = 0;
    self.window.rootViewController = splashVC;
    [self.window makeKeyAndVisible];

    [UIView animateWithDuration:0.3 animations:^{
        splashVC.view.alpha = 1;
    }];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.app application:application didFinishLaunching:launchOptions];
        [self.analyticsClient configureWithUserID:self.app.userUUID];
    });

    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    [self.app applicationDidBecomeActive:application];
}

- (void)applicationWillResignActive:(UIApplication *)application {
    [self.app applicationWillResignActive:application];
}

#pragma mark - OBAApplicationDelegate

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    return [self.app application:app open:url options:options];
}

- (UIApplication*)uiApplication {
    return [UIApplication sharedApplication];
}

- (void)performTestCrash {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-value"
    @[][1];
#pragma clang diagnostic pop
}

- (void)setIdleTimerDisabled:(BOOL)idleTimerDisabled {
    UIApplication.sharedApplication.idleTimerDisabled = idleTimerDisabled;
}

- (BOOL)idleTimerDisabled {
    return UIApplication.sharedApplication.idleTimerDisabled;
}

- (BOOL)registeredForRemoteNotifications {
    return UIApplication.sharedApplication.registeredForRemoteNotifications;
}

- (void)applicationReloadRootInterface:(OBAApplication*)application {
    void(^showRootController)(void) = ^{
        self.rootController = [[OBAClassicApplicationRootController alloc] initWithApplication:application];
        [UIView transitionWithView:self.window duration:0.3 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
            self.window.rootViewController = self.rootController;
        } completion:nil];
    };

    if ([OBAOnboardingNavigationController needsToOnboardWithApplication:application]) {
        self.window.rootViewController = [[OBAOnboardingNavigationController alloc] initWithApplication:application completion:^{
            showRootController();
            [UIView transitionWithView:self.window duration:0.5 options:UIViewAnimationOptionTransitionFlipFromLeft animations:nil completion:nil];
        }];
    } else {
        showRootController();
    }
}

- (BOOL)canOpenURL:(NSURL*)url {
    return [UIApplication.sharedApplication canOpenURL:url];
}

- (void)open:(NSURL * _Nonnull)url options:(NSDictionary<UIApplicationOpenExternalURLOptionsKey,id> * _Nonnull)options completionHandler:(void (^ _Nullable)(BOOL))completion {
    [UIApplication.sharedApplication openURL:url options:options completionHandler:completion];
}

- (NSDictionary<NSString*, NSString*>*)credits {
    return @{@"Firebase": @"https://raw.githubusercontent.com/firebase/firebase-ios-sdk/master/LICENSE"};
}

- (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)userActivity restorationHandler:(void(^)(NSArray<id<UIUserActivityRestoring>> *restorableObjects))restorationHandler {
    return [self.app application:application continue:userActivity restorationHandler:restorationHandler];
}

#pragma mark - Push Notifications

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    [self.pushService didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    [self.pushService didFailToRegisterForRemoteNotificationsWithError:error];
}

- (BOOL)isRegisteredForRemoteNotifications {
    return UIApplication.sharedApplication.registeredForRemoteNotifications;
}

@end
