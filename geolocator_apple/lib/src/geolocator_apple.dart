import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:geolocator_apple/geolocator_apple.dart';

/// An implementation of [GeolocatorPlatform] that uses method channels.
class GeolocatorApple extends GeolocatorPlatform {
  /// The method channel used to interact with the native platform.
  static const _methodChannel =
      MethodChannel('flutter.baseflow.com/geolocator_apple');

  /// The event channel used to receive [Position] updates from the native
  /// platform.
  static const _eventChannel =
      EventChannel('flutter.baseflow.com/geolocator_updates_apple');

  /// The event channel used to receive [LocationServiceStatus] updates from the
  /// native platform.
  static const _serviceStatusEventChannel =
      EventChannel('flutter.baseflow.com/geolocator_service_updates_apple');

  /// Registers this class as the default instance of [GeolocatorPlatform].
  static void registerWith() {
    GeolocatorPlatform.instance = GeolocatorApple();
  }

  /// On Android devices you can set [forcedLocationManager]
  /// to true to force the plugin to use the [LocationManager] to determine the
  /// position instead of the [FusedLocationProviderClient]. On iOS this is
  /// ignored.
  bool forcedLocationManager = false;

  Stream<Position>? _positionStream;
  Stream<ServiceStatus>? _serviceStatusStream;

  @override
  Future<LocationPermission> checkPermission() async {
    try {
      // ignore: omit_local_variable_types
      final int permission =
          await _methodChannel.invokeMethod('checkPermission');

      return permission.toLocationPermission();
    } on PlatformException catch (e) {
      final error = _handlePlatformException(e);

      throw error;
    }
  }

  @override
  Future<LocationPermission> requestPermission() async {
    try {
      // ignore: omit_local_variable_types
      final int permission =
          await _methodChannel.invokeMethod('requestPermission');

      return permission.toLocationPermission();
    } on PlatformException catch (e) {
      final error = _handlePlatformException(e);

      throw error;
    }
  }

  @override
  Future<bool> isLocationServiceEnabled() async => _methodChannel
      .invokeMethod<bool>('isLocationServiceEnabled')
      .then((value) => value ?? false);

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async {
    try {
      final parameters = <String, dynamic>{
        'forceLocationManager': forceLocationManager,
      };

      final positionMap =
          await _methodChannel.invokeMethod('getLastKnownPosition', parameters);

      return positionMap != null ? Position.fromMap(positionMap) : null;
    } on PlatformException catch (e) {
      final error = _handlePlatformException(e);

      throw error;
    }
  }

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async {
    final int accuracy =
        await _methodChannel.invokeMethod('getLocationAccuracy');
    return LocationAccuracyStatus.values[accuracy];
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    try {
      Future<dynamic> positionFuture;

      var timeLimit = locationSettings?.timeLimit;

      if (timeLimit != null) {
        positionFuture = _methodChannel
            .invokeMethod(
              'getCurrentPosition',
              locationSettings?.toJson(),
            )
            .timeout(timeLimit);
      } else {
        positionFuture = _methodChannel.invokeMethod(
          'getCurrentPosition',
          locationSettings?.toJson(),
        );
      }

      final positionMap = await positionFuture;
      return Position.fromMap(positionMap);
    } on PlatformException catch (e) {
      final error = _handlePlatformException(e);

      throw error;
    }
  }

  @override
  Stream<ServiceStatus> getServiceStatusStream() {
    if (_serviceStatusStream != null) {
      return _serviceStatusStream!;
    }
    var serviceStatusStream =
        _serviceStatusEventChannel.receiveBroadcastStream();

    _serviceStatusStream = serviceStatusStream
        .map((dynamic element) => ServiceStatus.values[element as int])
        .handleError((error) {
      _serviceStatusStream = null;
      if (error is PlatformException) {
        error = _handlePlatformException(error);
      }
      throw error;
    });

    return _serviceStatusStream!;
  }

  @override
  Stream<Position> getPositionStream({
    LocationSettings? locationSettings,
  }) {
    if (_positionStream != null) {
      return _positionStream!;
    }
    var originalStream = _eventChannel.receiveBroadcastStream(
      locationSettings?.toJson(),
    );
    var positionStream = _wrapStream(originalStream);

    var timeLimit = locationSettings?.timeLimit;

    if (timeLimit != null) {
      positionStream = positionStream.timeout(
        timeLimit,
        onTimeout: (s) {
          _positionStream = null;
          s.addError(TimeoutException(
            'Time limit reached while waiting for position update.',
            timeLimit,
          ));
          s.close();
        },
      );
    }

    _positionStream = positionStream
        .map<Position>((dynamic element) =>
            Position.fromMap(element.cast<String, dynamic>()))
        .handleError(
      (error) {
        if (error is PlatformException) {
          error = _handlePlatformException(error);
        }
        throw error;
      },
    );
    return _positionStream!;
  }

  Stream<dynamic> _wrapStream(Stream<dynamic> incoming) {
    return incoming.asBroadcastStream(onCancel: (subscription) {
      subscription.cancel();
      _positionStream = null;
    });
  }

  @override
  Future<LocationAccuracyStatus> requestTemporaryFullAccuracy({
    required String purposeKey,
  }) async {
    try {
      final int status = await _methodChannel.invokeMethod(
        'requestTemporaryFullAccuracy',
        <String, dynamic>{
          'purposeKey': purposeKey,
        },
      );
      return LocationAccuracyStatus.values[status];
    } on PlatformException catch (e) {
      final error = _handlePlatformException(e);
      throw error;
    }
  }

  @override
  Future<bool> openAppSettings() async => _methodChannel
      .invokeMethod<bool>('openAppSettings')
      .then((value) => value ?? false);

  @override
  Future<bool> openLocationSettings() async => _methodChannel
      .invokeMethod<bool>('openLocationSettings')
      .then((value) => value ?? false);

  /// Starts the background location service.
  ///
  /// The [locationSettings] specifies the configuration for the background
  /// location updates, including the callback, interval, and distance filter.
  ///
  /// The [locationSettings] MUST be an instance of [AppleSettings] and MUST
  /// contain a [BackgroundSettings] instance.
  Future<bool> startBackground(LocationSettings locationSettings) async {
    if (locationSettings is! AppleSettings ||
        locationSettings.backgroundSettings == null) {
      throw StateError(
          'Background settings must be provided in AppleSettings to start background location.');
    }

    final dispatcherHandle =
        PluginUtilities.getCallbackHandle(_backgroundCallbackDispatcher);

    if (dispatcherHandle == null) {
      return false;
    }

    final json = locationSettings.toJson();
    json['backgroundSettings']['dispatcherHandle'] =
        dispatcherHandle.toRawHandle();

    return await _methodChannel.invokeMethod('startBackground', json) ?? false;
  }

  /// Stops the background location service.
  Future<bool> stopBackground() async {
    return await _methodChannel.invokeMethod('stopBackground') ?? false;
  }

  /// Returns whether the background location service is running.
  Future<bool> isBackgroundRunning() async {
    return await _methodChannel.invokeMethod('isBackgroundRunning') ?? false;
  }

  Exception _handlePlatformException(PlatformException exception) {
    switch (exception.code) {
      case 'ACTIVITY_MISSING':
        return ActivityMissingException(exception.message);
      case 'LOCATION_SERVICES_DISABLED':
        return const LocationServiceDisabledException();
      case 'LOCATION_SUBSCRIPTION_ACTIVE':
        return const AlreadySubscribedException();
      case 'PERMISSION_DEFINITIONS_NOT_FOUND':
        return PermissionDefinitionsNotFoundException(exception.message);
      case 'PERMISSION_DENIED':
        return PermissionDeniedException(exception.message);
      case 'PERMISSION_REQUEST_IN_PROGRESS':
        return PermissionRequestInProgressException(exception.message);
      case 'LOCATION_UPDATE_FAILURE':
        return PositionUpdateException(exception.message);
      default:
        return exception;
    }
  }
}

@pragma('vm:entry-point')
void _backgroundCallbackDispatcher() {
  const MethodChannel backgroundChannel =
      MethodChannel('flutter.baseflow.com/geolocator_apple_background');

  WidgetsFlutterBinding.ensureInitialized();
  print('GeolocatorApple: _backgroundCallbackDispatcher initialized');

  backgroundChannel.setMethodCallHandler((MethodCall call) async {
    print('GeolocatorApple: received method call ${call.method}');
    if (call.method == 'onLocationUpdate') {
      final Map<dynamic, dynamic> args = call.arguments;
      final int callbackHandleRaw = args['callbackHandle'];
      final Map<dynamic, dynamic> positionMap = args['position'];

      print('GeolocatorApple: dispatching location update to callback handle $callbackHandleRaw');

      final Function? callback = PluginUtilities.getCallbackFromHandle(
          CallbackHandle.fromRawHandle(callbackHandleRaw));

      if (callback != null) {
        final Position position = Position.fromMap(positionMap);
        callback(position);
        print('GeolocatorApple: callback invoked successfully');
      } else {
        print('GeolocatorApple: could not find callback for handle $callbackHandleRaw');
      }
    }
  });

  print('GeolocatorApple: signaling initialization complete to native');
  backgroundChannel.invokeMethod('initialized');
}
