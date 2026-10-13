import 'dart:async';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:ui';

import 'package:baseflow_plugin_template/baseflow_plugin_template.dart';
import 'package:flutter/material.dart';
import 'package:geolocator_android/geolocator_android.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Defines the main theme color.
final MaterialColor themeMaterialColor =
    BaseflowPluginExample.createMaterialColor(
        const Color.fromRGBO(48, 49, 60, 1));

const String _kBackgroundPositionsKey = 'background_positions';
const String _kIsolateName = 'geolocator_background_isolate';

@pragma('vm:entry-point')
void backgroundCallback(Position position) async {
  print(position);
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final List<String> positions =
      prefs.getStringList(_kBackgroundPositionsKey) ?? [];
  positions.add(position.toString());
  await prefs.setStringList(_kBackgroundPositionsKey, positions);

  final SendPort? sendPort = IsolateNameServer.lookupPortByName(_kIsolateName);
  sendPort?.send(position.toString());
}

final locationServiceSettings = AndroidSettings(
    accuracy: LocationAccuracy.best,
    distanceFilter: 10,
    intervalDuration: const Duration(seconds: 1),
    forceLocationManager: false,
    useMSLAltitude: true,
    foregroundNotificationConfig: const ForegroundNotificationConfig(
      notificationText:
          "Example app will continue to receive your location even when you aren't using it",
      notificationTitle: "Running in Background",
      enableWakeLock: true,
      setOngoing: true,
      color: Colors.amber,
    ),
    backgroundSettings: BackgroundSettings(
      callback: backgroundCallback,
      intervalDuration: const Duration(seconds: 5),
      distanceFilter: 0,
    ));

void main() {
  runApp(const GeolocatorWidget());
}

/// Example [Widget] showing the functionalities of the geolocator plugin.
class GeolocatorWidget extends StatefulWidget {
  /// Creates a [PermissionHandlerWidget].
  const GeolocatorWidget({
    super.key,
  });

  /// Create a page containing the functionality of this plugin
  static ExamplePage createPage() {
    return ExamplePage(
        Icons.location_on, (context) => const GeolocatorWidget());
  }

  @override
  State<GeolocatorWidget> createState() {
    return _GeolocatorWidgetState();
  }
}

class _GeolocatorWidgetState extends State<GeolocatorWidget> {
  static const String _kLocationServicesDisabledMessage =
      'Location services are disabled.';
  static const String _kPermissionDeniedMessage = 'Permission denied.';
  static const String _kPermissionDeniedForeverMessage =
      'Permission denied forever.';
  static const String _kPermissionGrantedMessage = 'Permission granted.';

  final GeolocatorPlatform geolocatorAndroid = GeolocatorPlatform.instance;
  final List<_PositionItem> _positionItems = <_PositionItem>[];
  final List<String> _backgroundPositions = <String>[];
  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<ServiceStatus>? _serviceStatusStreamSubscription;
  bool _isBackgroundRunning = false;
  final ReceivePort _receivePort = ReceivePort();

  @override
  void initState() {
    super.initState();
    _toggleServiceStatusStream();
    _initBackgroundState();
  }

  Future<void> _initBackgroundState() async {
    IsolateNameServer.registerPortWithName(
        _receivePort.sendPort, _kIsolateName);
    _receivePort.listen((dynamic message) {
      if (message is String) {
        setState(() {
          _backgroundPositions.add(message);
        });
      }
    });

    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _backgroundPositions
          .addAll(prefs.getStringList(_kBackgroundPositionsKey) ?? []);
    });

    final isRunning =
        await (geolocatorAndroid as GeolocatorAndroid).isBackgroundRunning();
    setState(() {
      _isBackgroundRunning = isRunning;
    });
  }

  PopupMenuButton _createActions() {
    return PopupMenuButton(
      elevation: 40,
      onSelected: (value) async {
        switch (value) {
          case 1:
            _getLocationAccuracy();
            break;
          case 2:
            _requestTemporaryFullAccuracy();
            break;
          case 3:
            _openAppSettings();
            break;
          case 4:
            _openLocationSettings();
            break;
          case 5:
            setState(_positionItems.clear);
            break;
          default:
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 1,
          child: Text("Get Location Accuracy"),
        ),
        if (Platform.isIOS)
          const PopupMenuItem(
            value: 2,
            child: Text("Request Temporary Full Accuracy"),
          ),
        const PopupMenuItem(
          value: 3,
          child: Text("Open App Settings"),
        ),
        if (Platform.isAndroid)
          const PopupMenuItem(
            value: 4,
            child: Text("Open Location Settings"),
          ),
        const PopupMenuItem(
          value: 5,
          child: Text("Clear"),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const sizedBox = SizedBox(
      height: 10,
    );

    return BaseflowPluginExample(
        pluginName: 'Geolocator',
        githubURL: 'https://github.com/Baseflow/flutter-geolocator',
        pubDevURL: 'https://pub.dev/packages/geolocator',
        appBarActions: [
          _createActions()
        ],
        pages: [
          ExamplePage(
            Icons.location_on,
            (context) => Scaffold(
              backgroundColor: Theme.of(context).colorScheme.surface,
              body: ListView.builder(
                itemCount: _positionItems.length,
                itemBuilder: (context, index) {
                  final positionItem = _positionItems[index];

                  if (positionItem.type == _PositionItemType.log) {
                    return ListTile(
                      title: Text(positionItem.displayValue,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          )),
                    );
                  } else {
                    return Card(
                      child: ListTile(
                        tileColor: themeMaterialColor,
                        title: Text(
                          positionItem.displayValue,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    );
                  }
                },
              ),
              floatingActionButton: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FloatingActionButton(
                    onPressed: _toggleListening,
                    tooltip: (_positionStreamSubscription == null)
                        ? 'Start position updates'
                        : _positionStreamSubscription!.isPaused
                            ? 'Resume'
                            : 'Pause',
                    backgroundColor: _determineButtonColor(),
                    heroTag: 'listening',
                    child: (_positionStreamSubscription == null ||
                            _positionStreamSubscription!.isPaused)
                        ? const Icon(Icons.play_arrow)
                        : const Icon(Icons.pause),
                  ),
                  sizedBox,
                  FloatingActionButton(
                    onPressed: _toggleBackground,
                    tooltip: _isBackgroundRunning
                        ? 'Stop background'
                        : 'Start background',
                    backgroundColor:
                        _isBackgroundRunning ? Colors.green : Colors.red,
                    heroTag: 'background',
                    child: const Icon(Icons.history),
                  ),
                  sizedBox,
                  FloatingActionButton(
                    onPressed: _getCurrentPosition,
                    heroTag: 'current',
                    child: const Icon(Icons.my_location),
                  ),
                  sizedBox,
                  FloatingActionButton(
                    onPressed: _getLastKnownPosition,
                    heroTag: 'last',
                    child: const Icon(Icons.bookmark),
                  ),
                ],
              ),
            ),
          ),
          ExamplePage(
            Icons.history,
            (context) => Scaffold(
              backgroundColor: Theme.of(context).colorScheme.surface,
              appBar: AppBar(
                title: const Text('Background Locations'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove(_kBackgroundPositionsKey);
                      setState(() {
                        _backgroundPositions.clear();
                      });
                    },
                  ),
                ],
              ),
              body: ListView.builder(
                itemCount: _backgroundPositions.length,
                itemBuilder: (context, index) {
                  final position = _backgroundPositions[index];
                  return Card(
                    child: ListTile(
                      tileColor: themeMaterialColor,
                      title: Text(
                        position,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ]);
  }

  Future<void> _getCurrentPosition() async {
    final hasPermission = await _handlePermission();

    if (!hasPermission) {
      return;
    }

    final position = await geolocatorAndroid.getCurrentPosition();
    _updatePositionList(
      _PositionItemType.position,
      _displayPosition(position),
    );
  }

  Future<bool> _handlePermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await geolocatorAndroid.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the
      // App to enable the location services.
      _updatePositionList(
        _PositionItemType.log,
        _kLocationServicesDisabledMessage,
      );

      return false;
    }

    permission = await geolocatorAndroid.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await geolocatorAndroid.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        _updatePositionList(
          _PositionItemType.log,
          _kPermissionDeniedMessage,
        );

        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      _updatePositionList(
        _PositionItemType.log,
        _kPermissionDeniedForeverMessage,
      );

      return false;
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    _updatePositionList(
      _PositionItemType.log,
      _kPermissionGrantedMessage,
    );
    return true;
  }

  void _updatePositionList(_PositionItemType type, String displayValue) {
    _positionItems.add(_PositionItem(type, displayValue));
    setState(() {});
  }

  bool _isListening() => !(_positionStreamSubscription == null ||
      _positionStreamSubscription!.isPaused);

  Color _determineButtonColor() {
    return _isListening() ? Colors.green : Colors.red;
  }

  void _toggleServiceStatusStream() {
    if (_serviceStatusStreamSubscription == null) {
      final serviceStatusStream = geolocatorAndroid.getServiceStatusStream();
      _serviceStatusStreamSubscription =
          serviceStatusStream.handleError((error) {
        _serviceStatusStreamSubscription?.cancel();
        _serviceStatusStreamSubscription = null;
      }).listen((serviceStatus) {
        String serviceStatusValue;
        if (serviceStatus == ServiceStatus.enabled) {
          serviceStatusValue = 'enabled';
        } else {
          serviceStatusValue = 'disabled';
        }
        _updatePositionList(
          _PositionItemType.log,
          'Location service has been $serviceStatusValue',
        );
      });
    }
  }

  Future<void> _toggleListening() async {
    final hasPermission = await _handlePermission();

    if (!hasPermission) {
      return;
    }

    if (_positionStreamSubscription == null) {
      final positionStream = geolocatorAndroid.getPositionStream(
          locationSettings: locationServiceSettings);
      _positionStreamSubscription = positionStream.handleError((error) {
        _positionStreamSubscription?.cancel();
        _positionStreamSubscription = null;
      }).listen((position) {
        debugPrint(position.altitude.toString());
        _updatePositionList(
          _PositionItemType.position,
          _displayPosition(position),
        );
      });
      _positionStreamSubscription?.pause();
    }

    setState(() {
      if (_positionStreamSubscription == null) {
        return;
      }

      String statusDisplayValue;
      if (_positionStreamSubscription!.isPaused) {
        _positionStreamSubscription!.resume();
        statusDisplayValue = 'resumed';
      } else {
        _positionStreamSubscription!.pause();
        statusDisplayValue = 'paused';
      }

      _updatePositionList(
        _PositionItemType.log,
        'Listening for position updates $statusDisplayValue',
      );
    });
  }

  Future<void> _toggleBackground() async {
    final hasPermission = await _handlePermission();

    if (!hasPermission) {
      return;
    }

    final geolocatorAndroidPlugin = (geolocatorAndroid as GeolocatorAndroid);
    final isRunning = await geolocatorAndroidPlugin.isBackgroundRunning();

    if (isRunning) {
      await geolocatorAndroidPlugin.stopBackground();
    } else {
      await geolocatorAndroidPlugin.startBackground(locationServiceSettings);
    }

    final newIsRunning = await geolocatorAndroidPlugin.isBackgroundRunning();
    setState(() {
      _isBackgroundRunning = newIsRunning;
    });
  }

  @override
  void dispose() {
    if (_positionStreamSubscription != null) {
      _positionStreamSubscription!.cancel();
      _positionStreamSubscription = null;
    }
    IsolateNameServer.removePortNameMapping(_kIsolateName);
    _receivePort.close();

    super.dispose();
  }

  void _getLastKnownPosition() async {
    final position = await geolocatorAndroid.getLastKnownPosition();
    if (position != null) {
      _updatePositionList(
        _PositionItemType.position,
        _displayPosition(position),
      );
    } else {
      _updatePositionList(
        _PositionItemType.log,
        'No last known position available',
      );
    }
  }

  String _displayPosition(Position position) {
    final verticalSpeed = position.hasVerticalSpeed
        ? '${position.verticalSpeed.toStringAsFixed(2)} m/s'
        : 'unavailable';
    final verticalSpeedAccuracy = position.hasVerticalSpeedAccuracy
        ? '${position.verticalSpeedAccuracy.toStringAsFixed(2)} m/s'
        : 'unavailable';
    return '${position.toString()}\nVertical speed: $verticalSpeed'
        '\nVertical speed accuracy: $verticalSpeedAccuracy';
  }

  void _getLocationAccuracy() async {
    final status = await geolocatorAndroid.getLocationAccuracy();
    _handleLocationAccuracyStatus(status);
  }

  void _requestTemporaryFullAccuracy() async {
    final status = await geolocatorAndroid.requestTemporaryFullAccuracy(
      purposeKey: "TemporaryPreciseAccuracy",
    );
    _handleLocationAccuracyStatus(status);
  }

  void _handleLocationAccuracyStatus(LocationAccuracyStatus status) {
    String locationAccuracyStatusValue;
    if (status == LocationAccuracyStatus.precise) {
      locationAccuracyStatusValue = 'Precise';
    } else if (status == LocationAccuracyStatus.reduced) {
      locationAccuracyStatusValue = 'Reduced';
    } else {
      locationAccuracyStatusValue = 'Unknown';
    }
    _updatePositionList(
      _PositionItemType.log,
      '$locationAccuracyStatusValue location accuracy granted.',
    );
  }

  void _openAppSettings() async {
    final opened = await geolocatorAndroid.openAppSettings();
    String displayValue;

    if (opened) {
      displayValue = 'Opened Application Settings.';
    } else {
      displayValue = 'Error opening Application Settings.';
    }

    _updatePositionList(
      _PositionItemType.log,
      displayValue,
    );
  }

  void _openLocationSettings() async {
    final opened = await geolocatorAndroid.openLocationSettings();
    String displayValue;

    if (opened) {
      displayValue = 'Opened Location Settings';
    } else {
      displayValue = 'Error opening Location Settings';
    }

    _updatePositionList(
      _PositionItemType.log,
      displayValue,
    );
  }
}

enum _PositionItemType {
  log,
  position,
}

class _PositionItem {
  _PositionItem(this.type, this.displayValue);

  final _PositionItemType type;
  final String displayValue;
}
