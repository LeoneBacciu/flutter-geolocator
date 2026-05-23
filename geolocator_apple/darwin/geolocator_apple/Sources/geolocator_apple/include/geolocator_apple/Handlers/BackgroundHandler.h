#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

#if TARGET_OS_OSX
#import <FlutterMacOS/FlutterMacOS.h>
#else
#import <Flutter/Flutter.h>
#endif

@protocol DynamicPluginRegistrant <NSObject>
+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry;
@end

@interface BackgroundHandler : NSObject

- (void)startBackgroundWithDispatcherHandle:(int64_t)dispatcherHandle
                             callbackHandle:(int64_t)callbackHandle
                               timeInterval:(double)timeInterval
                             distanceFilter:(double)distanceFilter
                            desiredAccuracy:(CLLocationAccuracy)desiredAccuracy
            showBackgroundLocationIndicator:(BOOL)showBackgroundLocationIndicator
             allowBackgroundLocationUpdates:(BOOL)allowBackgroundLocationUpdates;

- (void)stopBackground;

- (BOOL)isBackgroundRunning;

- (void)onLocationUpdate:(CLLocation *)location;

@end
