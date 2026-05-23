#import <CoreLocation/CoreLocation.h>
#import "./include/geolocator_apple/GeolocatorPlugin.h"
#import "./include/geolocator_apple/GeolocatorPlugin_Test.h"
#import "./include/geolocator_apple/Constants/ErrorCodes.h"
#import "./include/geolocator_apple/Handlers/GeolocationHandler.h"
#import "./include/geolocator_apple/Handlers/PermissionHandler.h"
#import "./include/geolocator_apple/Handlers/PositionStreamHandler.h"
#import "./include/geolocator_apple/Handlers/BackgroundHandler.h"
#import "./include/geolocator_apple/Utils/ActivityTypeMapper.h"
#import "./include/geolocator_apple/Utils/AuthorizationStatusMapper.h"
#import "./include/geolocator_apple/Utils/LocationAccuracyMapper.h"
#import "./include/geolocator_apple/Utils/LocationDistanceMapper.h"
#import "./include/geolocator_apple/Utils/LocationMapper.h"
#import "./include/geolocator_apple/Utils/PermissionUtils.h"
#import "./include/geolocator_apple/Handlers/LocationAccuracyHandler.h"
#import "./include/geolocator_apple/Handlers/LocationServiceStreamHandler.h"

@interface GeolocatorPlugin ()

@property(strong, nonatomic, nonnull) GeolocationHandler *geolocationHandler;

@property(strong, nonatomic, nonnull) LocationAccuracyHandler *locationAccuracyHandler;

@property(strong, nonatomic, nonnull) PermissionHandler *permissionHandler;

@property(strong, nonatomic, nonnull) BackgroundHandler *backgroundHandler;

@end

@implementation GeolocatorPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel *methodChannel = [FlutterMethodChannel
                                         methodChannelWithName:@"flutter.baseflow.com/geolocator_apple"
                                         binaryMessenger:registrar.messenger];
  FlutterEventChannel *positionUpdatesEventChannel = [FlutterEventChannel
                                                      eventChannelWithName:@"flutter.baseflow.com/geolocator_updates_apple"
                                                      binaryMessenger:registrar.messenger];
  
  FlutterEventChannel *locationServiceUpdatesEventChannel = [FlutterEventChannel eventChannelWithName:@"flutter.baseflow.com/geolocator_service_updates_apple" binaryMessenger:registrar.messenger];
  
  GeolocatorPlugin *instance = [[GeolocatorPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:methodChannel];
  
  PositionStreamHandler *positionStreamHandler = [[PositionStreamHandler alloc] initWithGeolocationHandler:instance.createGeolocationHandler];
  [positionUpdatesEventChannel setStreamHandler:positionStreamHandler];
  
  LocationServiceStreamHandler *locationServiceStreamHandler = [[LocationServiceStreamHandler alloc] init];
  [locationServiceUpdatesEventChannel setStreamHandler:locationServiceStreamHandler];
  
}

- (GeolocationHandler *) createGeolocationHandler {
  if (!self.geolocationHandler) {
    self.geolocationHandler = [[GeolocationHandler alloc] init];
  }
  return self.geolocationHandler;
}

- (void) setGeolocationHandlerOverride:(GeolocationHandler *)geolocationHandler {
  self.geolocationHandler = geolocationHandler;
}

- (LocationAccuracyHandler *) createLocationAccuracyHandler {
  if (!self.locationAccuracyHandler) {
    self.locationAccuracyHandler = [[LocationAccuracyHandler alloc] init];
  }
  return self.locationAccuracyHandler;
}

- (void) setLocationAccuracyHandlerOverride:(LocationAccuracyHandler *)locationAccuracyHandler {
  self.locationAccuracyHandler = locationAccuracyHandler;
}

- (PermissionHandler *) createPermissionHandler {
  if (!self.permissionHandler) {
    self.permissionHandler = [[PermissionHandler alloc] init];
  }
  return self.permissionHandler;
}

- (void) setPermissionHandlerOverride:(PermissionHandler *)permissionHandler {
  self.permissionHandler = permissionHandler;
}

- (void) setBackgroundHandlerOverride:(BackgroundHandler *)backgroundHandler {
  self.backgroundHandler = backgroundHandler;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"checkPermission" isEqualToString:call.method]) {
    [self onCheckPermission:result];
  } else if ([@"requestPermission" isEqualToString:call.method]) {
    [self onRequestPermission:result];
  } else if ([@"isLocationServiceEnabled" isEqualToString:call.method]) {
    [self onIsLocationServiceEnabled:result];
  } else if ([@"getLastKnownPosition" isEqualToString:call.method]) {
    [self onGetLastKnownPosition:result];
  } else if ([@"getCurrentPosition" isEqualToString:call.method]) {
    [self onGetCurrentPositionWithArguments:call.arguments
                                     result:result];
  } else if ([@"startBackground" isEqualToString:call.method]) {
    [self onStartBackgroundWithArguments:call.arguments
                                  result:result];
  } else if ([@"stopBackground" isEqualToString:call.method]) {
    [self onStopBackground:result];
  } else if ([@"isBackgroundRunning" isEqualToString:call.method]) {
    [self onIsBackgroundRunning:result];
  } else if([@"getLocationAccuracy" isEqualToString:call.method]) {
    [[self createLocationAccuracyHandler] getLocationAccuracyWithResult:result];
  } else if([@"requestTemporaryFullAccuracy" isEqualToString:call.method]) {
    NSString* purposeKey = (NSString *)call.arguments[@"purposeKey"];
    [[self createLocationAccuracyHandler] requestTemporaryFullAccuracyWithResult:result
                                                                   purposeKey:purposeKey];
  } else if ([@"openAppSettings" isEqualToString:call.method]) {
    [self openSettings:result];
  } else if ([@"openLocationSettings" isEqualToString:call.method]) {
    [self openSettings:result];
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (void)onCheckPermission:(FlutterResult) result {
  CLAuthorizationStatus status = [[self createPermissionHandler] checkPermission];
  result([AuthorizationStatusMapper toDartIndex:status]);
}

- (void)onRequestPermission:(FlutterResult)result {
  [[self createPermissionHandler]
   requestPermission:^(CLAuthorizationStatus status) {
    result([AuthorizationStatusMapper toDartIndex:status]);
  }
   errorHandler:^(NSString *errorCode, NSString *errorDescription) {
    result([FlutterError errorWithCode: errorCode
                               message: errorDescription
                               details: nil]);
  }];
}

- (void)onIsLocationServiceEnabled:(FlutterResult)result {
  dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    BOOL isEnabled = [CLLocationManager locationServicesEnabled];
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        result([NSNumber numberWithBool:isEnabled]);
    });
  });
}

- (void)onGetLastKnownPosition:(FlutterResult)result {
  if (![[self createPermissionHandler] hasPermission]) {
    result([FlutterError errorWithCode: GeolocatorErrorPermissionDenied
                               message:@"User denied permissions to access the device's location."
                               details:nil]);
    return;
  }
  
  CLLocation *location = [self.createGeolocationHandler getLastKnownPosition];
  result([LocationMapper toDictionary:location]);
}

- (void)onGetCurrentPositionWithArguments:(id _Nullable)arguments
                                   result:(FlutterResult)result {
  if (![[self createPermissionHandler] hasPermission]) {
    result([FlutterError errorWithCode: GeolocatorErrorPermissionDenied
                               message:@"User denied permissions to access the device's location."
                               details:nil]);
    return;
  }
  
  CLLocationAccuracy accuracy = [LocationAccuracyMapper toCLLocationAccuracy:(NSNumber *)arguments[@"accuracy"]];
  GeolocationHandler *geolocationHandler = [self createGeolocationHandler];
  
  [geolocationHandler requestPositionWithDesiredAccuracy:accuracy
                                           resultHandler:^(CLLocation *location) {
    result([LocationMapper toDictionary:location]);
  }
                                            errorHandler:^(NSString *errorCode, NSString *errorDescription){
    result([FlutterError errorWithCode: errorCode
                               message: errorDescription
                               details: nil]);
  }];
}

- (void)onStartBackgroundWithArguments:(id _Nullable)arguments
                                result:(FlutterResult)result {
  if (![[self createPermissionHandler] hasPermission]) {
    result([FlutterError errorWithCode: GeolocatorErrorPermissionDenied
                               message:@"User denied permissions to access the device's location."
                               details:nil]);
    return;
  }

  NSDictionary *backgroundSettings = arguments[@"backgroundSettings"];
  int64_t dispatcherHandle = [backgroundSettings[@"dispatcherHandle"] longLongValue];
  int64_t callbackHandle = [backgroundSettings[@"callbackHandle"] longLongValue];
  double timeInterval = [backgroundSettings[@"intervalDuration"] doubleValue] / 1000.0;
  double distanceFilter = [backgroundSettings[@"distanceFilter"] doubleValue];

  CLLocationAccuracy accuracy = [LocationAccuracyMapper toCLLocationAccuracy:(NSNumber *)arguments[@"accuracy"]];
  NSNumber* allowBackgroundLocationUpdates = arguments[@"allowBackgroundLocationUpdates"];
  NSNumber* showBackgroundLocationIndicator = arguments[@"showBackgroundLocationIndicator"];
  NSNumber* pauseLocationUpdatesAutomatically = arguments[@"pauseLocationUpdatesAutomatically"];
  CLActivityType activityType = [ActivityTypeMapper toCLActivityType:(NSNumber *)arguments[@"activityType"]];

  [[self createBackgroundHandler] startBackgroundWithDispatcherHandle:dispatcherHandle
                                                       callbackHandle:callbackHandle
                                                         timeInterval:timeInterval
                                                       distanceFilter:distanceFilter
                                                      desiredAccuracy:accuracy
                                    pauseLocationUpdatesAutomatically:pauseLocationUpdatesAutomatically && [pauseLocationUpdatesAutomatically boolValue]
                                                         activityType:activityType
                                      showBackgroundLocationIndicator:showBackgroundLocationIndicator && [showBackgroundLocationIndicator boolValue]
                                       allowBackgroundLocationUpdates:[allowBackgroundLocationUpdates boolValue]];

  result(@YES);
}

- (void)onStopBackground:(FlutterResult)result {
  [[self createBackgroundHandler] stopBackground];
  result(@YES);
}

- (void)onIsBackgroundRunning:(FlutterResult)result {
  BOOL isRunning = [[self createBackgroundHandler] isBackgroundRunning];
  result(@(isRunning));
}

- (BackgroundHandler *) createBackgroundHandler {
  if (!self.backgroundHandler) {
    self.backgroundHandler = [[BackgroundHandler alloc] init];
  }
  return self.backgroundHandler;
}

- (void)openSettings:(FlutterResult)result {
#if TARGET_OS_OSX
  NSString *urlString = @"x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices";
  BOOL success = [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urlString]];
  result([[NSNumber alloc] initWithBool:success]);
#else
  [[UIApplication sharedApplication]
   openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]
   options:[[NSDictionary alloc] init]
   completionHandler:^(BOOL success) {
    result([[NSNumber alloc] initWithBool:success]);
  }];
#endif
}
@end
