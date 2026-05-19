import 'dart:ui';

import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

/// Represents background specific settings for Android.
class BackgroundSettings {
  /// Initializes a new [BackgroundSettings] instance.
  BackgroundSettings({
    required this.callback,
    this.intervalDuration = const Duration(seconds: 5),
    this.distanceFilter = 0,
  });

  /// The callback that will be invoked in the background isolate.
  final void Function(Position position) callback;

  /// The desired interval for active location updates in the background.
  final Duration intervalDuration;

  /// The minimum distance (measured in meters) a device must move horizontally
  /// before an update event is generated in the background.
  final int distanceFilter;

  /// Converts the [BackgroundSettings] instance to a [Map] that can be
  /// serialized to JSON.
  Map<String, dynamic> toJson() {
    final callbackHandle = PluginUtilities.getCallbackHandle(callback);
    return {
      'callbackHandle': callbackHandle?.toRawHandle(),
      'intervalDuration': intervalDuration.inMilliseconds,
      'distanceFilter': distanceFilter,
    };
  }
}
