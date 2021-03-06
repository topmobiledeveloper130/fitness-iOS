//
//  AppDelegate.m
//  EverybodyRun
//
//  Created by star on 1/28/16.
//  Copyright © 2016 samule. All rights reserved.
//

#import "AppDelegate.h"
#import <FBSDKCoreKit/FBSDKCoreKit.h>
#import <Pushwoosh/PushNotificationManager.h>
#import "HomeViewController.h"
#import "Branch.h"
#import <Fabric/Fabric.h>
#import <Mapbox/Mapbox.h>

@interface AppDelegate () <CLLocationManagerDelegate, PushNotificationDelegate>
{
    CLGeocoder              *geocoder;
    
    BOOL                    locationIssueNotified;
    BOOL                    locationSuccessNotified;
}

@end

@implementation AppDelegate
@synthesize locationManager;

#define SYSTEM_VERSION_GRATERTHAN_OR_EQUALTO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    sleep(2);
    
    //Location.
    [self startUpdatingLocation];
    [self initAppearenceForUI];
    
    [Fabric with:@[[Branch class], [MGLAccountManager class]]];
    NSLog(@"version = %ld", (long)[MGLAccountManager version]);
    
    //Branch.
    Branch *branch = [Branch getInstance];
    [branch initSessionWithLaunchOptions:launchOptions andRegisterDeepLinkHandler:^(NSDictionary *params, NSError *error) {
        // params are the deep linked params associated with the link that the user clicked before showing up.
        NSLog(@"deep link data: %@", [params description]);
        
        if(params != nil && [[params allKeys] containsObject: @"event_id"])
        {
            int event_id = [[params valueForKey: @"event_id"] intValue];
            [[NetworkClient sharedClient] getSingleEvent: event_id
                                                 user_id: [AppEngine sharedInstance].currentUser.user_id
                                                 success:^(NSDictionary *dicEvent) {
                                                     
                                                     NSLog(@"response = %@", dicEvent);
                                                     if(dicEvent != nil && [dicEvent isKindOfClass: [NSDictionary class]])
                                                     {
                                                         Event* e = [[Event alloc] initWithDictionary: dicEvent];
                                                         [[CoreHelper sharedInstance] addEvent: e];
                                                         
                                                         if(self.homeView)
                                                         {
                                                             [(HomeViewController*)self.homeView showEventInCenter: e];
                                                         }
                                                     }
                                                     
                                                 } failure:^(NSError *error) {
                                                     
                                                 }];
        }
        
    }];
    
    // Override point for customization after application launch.
    [[FBSDKApplicationDelegate sharedInstance] application:application
                             didFinishLaunchingWithOptions:launchOptions];
    
    
//    // Checking if app is running iOS 8
//    if ([application respondsToSelector:@selector(registerForRemoteNotifications)]) {
//        // Register device for iOS8
//        UIUserNotificationSettings *notificationSettings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound categories:nil];
//        [application registerUserNotificationSettings:notificationSettings];
//        [application registerForRemoteNotifications];
//    } else {
//        // Register device for iOS7
//        [application registerForRemoteNotificationTypes:UIRemoteNotificationTypeAlert | UIRemoteNotificationTypeSound | UIRemoteNotificationTypeBadge];
//    }
    if(SYSTEM_VERSION_GRATERTHAN_OR_EQUALTO(@"10.0")){
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        center.delegate = self;
        [center requestAuthorizationWithOptions:(UNAuthorizationOptionSound | UNAuthorizationOptionAlert | UNAuthorizationOptionBadge) completionHandler:^(BOOL granted, NSError * _Nullable error){
            if(!error){
                [[UIApplication sharedApplication] registerForRemoteNotifications];
            }
        }];
    }
    else {
        [application registerUserNotificationSettings:[UIUserNotificationSettings settingsForTypes:(UIUserNotificationTypeSound | UIUserNotificationTypeAlert | UIUserNotificationTypeBadge) categories:nil]];
        [application registerForRemoteNotifications];
    }
    
    // check launch notification (optional)
    NSDictionary *launchNotification = [PushNotificationManager pushManager].launchNotification;
    if (launchNotification) {
        NSError *error;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:launchNotification
                                                           options:NSJSONWritingPrettyPrinted
                                                             error:&error];
        
        if (!jsonData) {
            NSLog(@"Got an error: %@", error);
        } else {
            NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            NSLog(@"Received launch notification with data: %@", jsonString);
        }
    }
    else {
        NSLog(@"No launch notification");
    }
    
    //-----------PUSHWOOSH PART-----------
    // set custom delegate for push handling, in our case - view controller
    [PushNotificationManager pushManager].delegate = self;
    
    // set default Pushwoosh delegate for iOS10 foreground push handling
//    [UNUserNotificationCenter currentNotificationCenter].delegate = [PushNotificationManager pushManager].notificationCenterDelegate;
    
    // handling push on app start
    [[PushNotificationManager pushManager] handlePushReceived:launchOptions];
    
    // make sure we count app open in Pushwoosh stats
    [[PushNotificationManager pushManager] sendAppOpen];
    
    // register for push notifications!
    [[PushNotificationManager pushManager] registerForPushNotifications];
    
    [[PushNotificationManager pushManager] startLocationTracking];
    
    return YES;
}

- (void) initAppearenceForUI
{
    //Search Bar.
    [[UITextField appearanceWhenContainedIn:[UISearchBar class], nil] setFont:[UIFont fontWithName: FONT_REGULAR size:13]];
    
    //Bar Button
    NSDictionary *barButtonAppearanceDict = @{NSFontAttributeName : [UIFont fontWithName: FONT_REGULAR size:13.0]};
    [[UIBarButtonItem appearance] setTitleTextAttributes:barButtonAppearanceDict forState:UIControlStateNormal];
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    [[Branch getInstance] handleDeepLink:url];
    return [[FBSDKApplicationDelegate sharedInstance] application:application
                                                          openURL:url
                                                sourceApplication:sourceApplication
                                                       annotation:annotation
            ];
}

- (BOOL)application:(UIApplication *)application continueUserActivity:(NSUserActivity *)userActivity restorationHandler:(void (^)(NSArray *))restorationHandler
{
    BOOL handledByBranch = [[Branch getInstance] continueUserActivity:userActivity];
    return handledByBranch;
}

// system push notification registration success callback, delegate to pushManager
- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    [[PushNotificationManager pushManager] handlePushRegistration:deviceToken];

    NSString *deviceTokenString = [[deviceToken description] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<>"]];
    deviceTokenString = [deviceTokenString stringByReplacingOccurrencesOfString:@" " withString:@""];
    [AppEngine sharedInstance].currentDeviceToken = deviceTokenString;
    NSLog(@"device token = %@", [AppEngine sharedInstance].currentDeviceToken);
    
//    UIAlertView *alert= [[UIAlertView alloc]initWithTitle:deviceTokenString message:Nil delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
//    [alert show];
}

// system push notification registration error callback, delegate to pushManager
- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    [[PushNotificationManager pushManager] handlePushRegistrationFailure:error];
}

//// system push notifications callback, delegate to pushManager
- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
    [[PushNotificationManager pushManager] handlePushReceived:userInfo];
    [[Branch getInstance] handlePushNotification:userInfo];
}
    
- (void)onDidFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
}


- (void) onPushAccepted: (PushNotificationManager *)pushManager withNotification:(NSDictionary *)pushNotification onStart:(BOOL)onStart {
    NSLog(@"Push notification received");
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
    
    if (SYSTEM_VERSION_GRATERTHAN_OR_EQUALTO(@"10.0")) {
        NSLog(@"iOS version>=10.0. let notificationcenter handle this one.");
        return;
    }
    
    NSLog(@"Remote Notification Received: %@", userInfo);
    
    [[PushNotificationManager pushManager] handlePushReceived:userInfo];
    [[Branch getInstance] handlePushNotification:userInfo];
    NSDictionary *userData = [[PushNotificationManager pushManager] getCustomPushDataAsNSDict:userInfo];
    if(userData != nil)
    {
        [self updateEventData: userData];
    }
    
    completionHandler(UIBackgroundFetchResultNewData);
    
    UIApplicationState state = [application applicationState];
    
    if (state == UIApplicationStateActive) {
        // do stuff when app is active
    } else {
        // do stuff when app is in background

    }

}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    
    //Called when a notification is delivered to a foreground app.
    NSLog(@"Remote Notification Received: %@", notification.request.content.userInfo);
    
    [[PushNotificationManager pushManager] handlePushReceived:notification.request.content.userInfo];
    [[Branch getInstance] handlePushNotification:notification.request.content.userInfo];
    NSDictionary *userData = [[PushNotificationManager pushManager] getCustomPushDataAsNSDict:notification.request.content.userInfo];
    if(userData != nil)
    {
        [self updateEventData: userData];
    }

    completionHandler(UNNotificationPresentationOptionAlert);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)())completionHandler {
    
    //Called to let your app know which action was selected by the user for a given notification.
    NSLog(@"Userinfo %@", response.notification.request.content.userInfo);
    NSDictionary *userData = [[PushNotificationManager pushManager] getCustomPushDataAsNSDict:response.notification.request.content.userInfo];
    if(userData != nil) {
        [self updateEventData:userData];
    }
    completionHandler();
}

- (void) updateEventNotification {
    if ([AppEngine sharedInstance].currentUser != nil) {
        [[NetworkClient sharedClient] getNotifications: [AppEngine sharedInstance].currentUser.user_id success:^(NSArray *array) {
            [AppEngine sharedInstance].currentUser.unread_notification_num = (int)[array count];
            [[NSNotificationCenter defaultCenter]postNotificationName:@"unReadEventNotification" object:nil];
            if ([array count]!=0) {
                [UIApplication sharedApplication].applicationIconBadgeNumber = (int)[array count];
            }
        } failure:^(NSError *error) {
            
        }];
    }
}

- (void) updateEventData: (NSDictionary*) userData
{

    if(userData != nil && [userData valueForKey: @"event_id"] != nil)
    {
        //Get Single Data.
        [[NetworkClient sharedClient] getSingleEvent: [[userData valueForKey: @"event_id"] intValue]
                                             user_id: [AppEngine sharedInstance].currentUser.user_id
                                             success:^(NSDictionary *dicEvent) {
                                                 
                                                 if(dicEvent != nil && [dicEvent isKindOfClass: [NSDictionary class]])
                                                 {
                                                     Event* e = [[Event alloc] initWithDictionary: dicEvent];
                                                     [[CoreHelper sharedInstance] addEvent: e];
                                                     
                                                     if(self.homeView != nil)
                                                     {
                                                         [(HomeViewController*)self.homeView updateEvent: e];
                                                     }
                                                 }
                                                 else
                                                 {
                                                     if(self.homeView != nil)
                                                     {
                                                         [(HomeViewController*)self.homeView removeEvent: [[userData valueForKey: @"event_id"] intValue]];
                                                     }
                                                 }
                                                 
                                             } failure:^(NSError *error) {
                                                 
                                             }];
        [self updateEventNotification];

    }
    
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    [self updateCurrentUserLocation];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    [self updateCurrentUserLocation];
    [self updateEventNotification];
    if(self.homeView != nil) {
        [(HomeViewController*)self.homeView applicationIsActive];
    }
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    
    [[UIApplication sharedApplication] cancelAllLocalNotifications];
    [UIApplication sharedApplication].applicationIconBadgeNumber = 0;
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}


- (void)startUpdatingLocation
{
    if(locationManager == nil)
    {
        locationSuccessNotified = NO;
        locationIssueNotified = NO;
        
        locationManager=[[CLLocationManager alloc] init];
        locationManager.delegate=self;
        locationManager.distanceFilter=kCLDistanceFilterNone;
        locationManager.desiredAccuracy=kCLLocationAccuracyHundredMeters;
        
        // Check for iOS 8. Without this guard the code will crash with "unknown selector" on iOS 7.
        if ([locationManager respondsToSelector:@selector(requestWhenInUseAuthorization)]) {
            [locationManager requestWhenInUseAuthorization];
        }
        
        [locationManager startUpdatingLocation];
        geocoder = [[CLGeocoder alloc] init];
    }
}

#pragma mark CLLocationManagerDelegate

+(AppDelegate*) getDelegate
{
    return (AppDelegate*)[[UIApplication sharedApplication] delegate];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    [AppEngine sharedInstance].locationServiceEnabled = NO;
    if (!locationIssueNotified)
    {
        locationIssueNotified = YES;
        locationSuccessNotified = NO;
        
        [[NSNotificationCenter defaultCenter] postNotificationName:LOCATIONSERVICEFAILEDNOTIFICATION object:nil];
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations
{
    if(locations != nil && [locations count] > 0)
    {
        CLLocation *current = [locations lastObject];
        
        [AppEngine sharedInstance].locationServiceEnabled = YES;
        [[AppEngine sharedInstance] setCurrentLatitude: current.coordinate.latitude];
        [[AppEngine sharedInstance] setCurrentLongitude: current.coordinate.longitude];
        
        if([AppEngine sharedInstance].currentUser != nil) {
            
            [AppEngine sharedInstance].currentUser.lat = [NSNumber numberWithDouble: current.coordinate.latitude];
            [AppEngine sharedInstance].currentUser.lng = [NSNumber numberWithDouble: current.coordinate.longitude];
            [self getAddressForLocation: current success:^(NSString *address) {
                
                BOOL needToUpdate = NO;
                if([AppEngine sharedInstance].currentUser.location == nil || [AppEngine sharedInstance].currentUser.location.length == 0){
                    needToUpdate = YES;
                }
                [AppEngine sharedInstance].currentUser.location = address;
                if(needToUpdate) {
                    [self updateCurrentUserLocation];
                }
                
            } failure:^{
                
            }];
        }
        
        if (!locationSuccessNotified)
        {
            locationIssueNotified = NO;
            locationSuccessNotified = YES;
            
            [[NSNotificationCenter defaultCenter] postNotificationName:LOCATIONSERVICESUCCESSNOTIFICATION object:nil];
        }
    }
}

- (void) getAddressForLocation: (CLLocation*) location
                       success:(void(^)(NSString *address)) success
                       failure:(void(^)(void))failure
{
    [geocoder reverseGeocodeLocation:location completionHandler:^(NSArray *placemarks, NSError *error)
     {
         if(placemarks != nil && [placemarks count] > 0)
         {
             CLPlacemark* placemark = [placemarks firstObject];
             NSArray *lines = placemark.addressDictionary[@"FormattedAddressLines"];
             NSString *addressString = [lines componentsJoinedByString:@" "];
             success(addressString);
         }
         else
         {
             failure();
         }
     }];
}

- (void) updateCurrentUserLocation {
    if([AppEngine sharedInstance].currentUser != nil) {
        NSLog(@"[AppEngine sharedInstance].currentUser = %@", [AppEngine sharedInstance].currentUser.location);
        [[NetworkClient sharedClient] updateUserLocation: [AppEngine sharedInstance].currentUser success:^{
            
        } failure:^(NSError *error) {
            
        }];
    }
}

@end
