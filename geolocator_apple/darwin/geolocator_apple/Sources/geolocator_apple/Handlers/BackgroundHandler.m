#import "../include/geolocator_apple/Handlers/BackgroundHandler.h"
#import "../include/geolocator_apple/Utils/LocationMapper.h"
#import <UserNotifications/UserNotifications.h>

@interface BackgroundHandler ()
@property (strong, nonatomic) FlutterEngine *backgroundEngine;
@property (strong, nonatomic) FlutterMethodChannel *backgroundChannel;
@property (assign, nonatomic) int64_t callbackHandle;
@property (assign, nonatomic) double timeInterval;
@property (assign, nonatomic) double distanceFilter;
@property (strong, nonatomic) CLLocation *lastLocation;
@property (assign, nonatomic) BOOL isDispatcherReady;
@end

@implementation BackgroundHandler

- (void)startBackgroundWithDispatcherHandle:(int64_t)dispatcherHandle
                             callbackHandle:(int64_t)callbackHandle
                               timeInterval:(double)timeInterval
                             distanceFilter:(double)distanceFilter {
  if (self.backgroundEngine) {
    NSLog(@"GeolocatorApple: Background isolate already started.");
    return;
  }

  NSLog(@"GeolocatorApple: Starting background isolate...");

  self.callbackHandle = callbackHandle;
  self.timeInterval = timeInterval;
  self.distanceFilter = distanceFilter;
  self.isDispatcherReady = NO;

  self.backgroundEngine = [[FlutterEngine alloc] initWithName:@"GeolocatorBackground" project:nil allowHeadlessExecution:YES];

  FlutterCallbackInformation *info = [FlutterCallbackCache lookupCallbackInformation:dispatcherHandle];
  if (!info) {
      NSLog(@"GeolocatorApple: Fatal: failed to find callback information for dispatcher.");
      return;
  }

  NSLog(@"GeolocatorApple: Creating engine with entrypoint: %@ in %@", info.callbackName, info.callbackLibraryPath);
  [self.backgroundEngine runWithEntrypoint:info.callbackName libraryURI:info.callbackLibraryPath];

  self.backgroundChannel = [FlutterMethodChannel methodChannelWithName:@"flutter.baseflow.com/geolocator_apple_background" binaryMessenger:self.backgroundEngine.binaryMessenger];

  __weak typeof(self) weakSelf = self;
  [self.backgroundChannel setMethodCallHandler:^(FlutterMethodCall *call, FlutterResult result) {
    NSLog(@"GeolocatorApple: received method call %@ from background isolate", call.method);
    if ([call.method isEqualToString:@"initialized"]) {
      weakSelf.isDispatcherReady = YES;
      [weakSelf showBackgroundNotification];
      result(@YES);
    } else {
      result(FlutterMethodNotImplemented);
    }
  }];
}

- (void)showBackgroundNotification {
  NSLog(@"GeolocatorApple: Showing background notification");
  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];

  [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                        completionHandler:^(BOOL granted, NSError * _Nullable error) {
    if (granted) {
      UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
      content.title = @"Background Location Tracking";
      content.body = @"Geolocator is currently tracking your location in the background.";
      content.sound = [UNNotificationSound defaultSound];

      UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1 repeats:NO];

      UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:@"GeolocatorBackgroundNotification"
                                                                           content:content
                                                                           trigger:trigger];

      [center addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
          if (error) {
              NSLog(@"GeolocatorApple: Error adding notification: %@", error);
          }
      }];
    } else {
        NSLog(@"GeolocatorApple: Notification permission denied");
    }
  }];
}

- (void)stopBackground {
  if (self.backgroundEngine) {
    NSLog(@"GeolocatorApple: Stopping background isolate...");
    [self.backgroundEngine destroyContext];
    self.backgroundEngine = nil;
    self.backgroundChannel = nil;
    self.isDispatcherReady = NO;
  }
}

- (BOOL)isBackgroundRunning {
  return self.backgroundEngine != nil;
}

- (void)onLocationUpdate:(CLLocation *)location {
  if (!self.isDispatcherReady) {
    NSLog(@"GeolocatorApple: Dropped location update because background isolate is not ready.");
    return;
  }

  if (self.lastLocation != nil) {
    NSTimeInterval timeSinceLastUpdate = [location.timestamp timeIntervalSinceDate:self.lastLocation.timestamp];
    CLLocationDistance distanceSinceLastUpdate = [location distanceFromLocation:self.lastLocation];

    if (timeSinceLastUpdate < self.timeInterval && distanceSinceLastUpdate < self.distanceFilter) {
      NSLog(@"GeolocatorApple: Dropped location update due to filters. Time: %f < %f, Distance: %f < %f", timeSinceLastUpdate, self.timeInterval, distanceSinceLastUpdate, self.distanceFilter);
      return;
    }
  }

  NSLog(@"GeolocatorApple: Dispatching location update to background isolate...");
  self.lastLocation = location;

  NSDictionary *arguments = @{
    @"callbackHandle": @(self.callbackHandle),
    @"position": [LocationMapper toDictionary:location]
  };

  [self.backgroundChannel invokeMethod:@"onLocationUpdate" arguments:arguments];
}

@end
