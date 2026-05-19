package com.baseflow.geolocator;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.Notification;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.location.Location;
import android.net.wifi.WifiManager;
import android.os.Binder;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.util.Log;

import java.util.HashMap;

import androidx.annotation.Nullable;

import com.baseflow.geolocator.errors.ErrorCodes;
import com.baseflow.geolocator.location.BackgroundNotification;
import com.baseflow.geolocator.location.ForegroundNotificationOptions;
import com.baseflow.geolocator.location.GeolocationManager;
import com.baseflow.geolocator.location.LocationClient;
import com.baseflow.geolocator.location.LocationMapper;
import com.baseflow.geolocator.location.LocationOptions;

import io.flutter.plugin.common.EventChannel;

public class GeolocatorLocationService extends Service {
  private static final String TAG = "FlutterGeolocator";
  private static final int ONGOING_NOTIFICATION_ID = 75415;
  private static final String CHANNEL_ID = "geolocator_channel_01";
  private static final String SHARED_PREFERENCES_NAME = "geolocator_background_preferences";
  private static final String CALLBACK_HANDLE_KEY = "callback_handle";
  private static final String DISPATCHER_HANDLE_KEY = "dispatcher_handle";
  private static final String TIME_INTERVAL_KEY = "time_interval";
  private static final String DISTANCE_FILTER_KEY = "distance_filter";

  private final String WAKELOCK_TAG = "GeolocatorLocationService:Wakelock";
  private final String WIFILOCK_TAG = "GeolocatorLocationService:WifiLock";
  private final LocalBinder binder = new LocalBinder(this);
  // Service is foreground
  private boolean isForeground = false;
  private int connectedEngines = 0;
  private int listenerCount = 0;
  @Nullable private Activity activity = null;
  @Nullable private GeolocationManager geolocationManager = null;
  @Nullable private LocationClient locationClient;
  @Nullable private LocationClient backgroundLocationClient;
  @Nullable private BackgroundExecutor backgroundExecutor;

  @Nullable private PowerManager.WakeLock wakeLock = null;
  @Nullable private WifiManager.WifiLock wifiLock = null;

  @Nullable private BackgroundNotification backgroundNotification = null;

  @Override
  public void onCreate() {
    super.onCreate();
    Log.d(TAG, "Creating service.");
  }

  @Override
  public int onStartCommand(Intent intent, int flags, int startId) {
    if (intent != null && intent.getAction() != null) {
      if (intent.getAction().equals("stop")) {
        stopBackgroundLocationService();
        return START_NOT_STICKY;
      }
    }

    // Attempt to restore background service if it was running.
    SharedPreferences prefs = getSharedPreferences(SHARED_PREFERENCES_NAME, Context.MODE_PRIVATE);
    long callbackHandle = prefs.getLong(CALLBACK_HANDLE_KEY, 0);
    long dispatcherHandle = prefs.getLong(DISPATCHER_HANDLE_KEY, 0);
    long timeInterval = prefs.getLong(TIME_INTERVAL_KEY, 0);
    long distanceFilter = prefs.getLong(DISTANCE_FILTER_KEY, 0);

    if (callbackHandle != 0 && dispatcherHandle != 0) {
      startBackgroundLocationService(callbackHandle, dispatcherHandle, timeInterval, distanceFilter);
    }

    return START_STICKY;
  }

  @Nullable
  @Override
  public IBinder onBind(Intent intent) {
    Log.d(TAG, "Binding to location service.");
    return binder;
  }

  @Override
  public boolean onUnbind(Intent intent) {
    Log.d(TAG, "Unbinding from location service.");
    return super.onUnbind(intent);
  }

  @Override
  public void onDestroy() {
    Log.d(TAG, "Destroying location service.");

    stopLocationService();
    stopBackgroundLocationService();
    disableBackgroundMode();
    geolocationManager = null;
    backgroundNotification = null;

    Log.d(TAG, "Destroyed location service.");
    super.onDestroy();
  }

  public boolean isBackgroundRunning() {
    return backgroundExecutor != null && backgroundExecutor.isRunning();
  }

  public void startBackgroundLocationService(
      long callbackHandle, long dispatcherHandle, long timeInterval, long distanceFilter) {
    Log.d(TAG, "Starting background location service.");

    // Store handles in SharedPreferences to allow restarting the service.
    SharedPreferences prefs = getSharedPreferences(SHARED_PREFERENCES_NAME, Context.MODE_PRIVATE);
    prefs
        .edit()
        .putLong(CALLBACK_HANDLE_KEY, callbackHandle)
        .putLong(DISPATCHER_HANDLE_KEY, dispatcherHandle)
        .putLong(TIME_INTERVAL_KEY, timeInterval)
        .putLong(DISTANCE_FILTER_KEY, distanceFilter)
        .apply();

    if (backgroundExecutor == null) {
      backgroundExecutor = new BackgroundExecutor();
    }

    if (!backgroundExecutor.isRunning()) {
      backgroundExecutor.startScanning(this.getApplicationContext(), dispatcherHandle);
    }

    if (geolocationManager == null) {
      geolocationManager = GeolocationManager.getInstance();
    }

    if (backgroundLocationClient != null) {
      geolocationManager.stopPositionUpdates(backgroundLocationClient);
    }

    // Background updates have a separate interval and distance filter.
    LocationOptions options =
        LocationOptions.parseArguments(
            new HashMap<String, Object>() {
              {
                put("timeInterval", (int) timeInterval);
                put("distanceFilter", (int) distanceFilter);
                put("accuracy", 3); // High accuracy by default for background.
                put("useMSLAltitude", false);
              }
            });

    backgroundLocationClient =
        geolocationManager.createLocationClient(this.getApplicationContext(), false, options);

    geolocationManager.startPositionUpdates(
        backgroundLocationClient,
        null,
        (Location location) -> {
          if (backgroundExecutor != null) {
            backgroundExecutor.onLocationUpdate(callbackHandle, location);
          }
        },
        (ErrorCodes errorCodes) -> {
          Log.e(TAG, "Error during background location update: " + errorCodes);
        });
  }

  public void stopBackgroundLocationService() {
    Log.d(TAG, "Stopping background location service.");

    if (backgroundLocationClient != null && geolocationManager != null) {
      geolocationManager.stopPositionUpdates(backgroundLocationClient);
      backgroundLocationClient = null;
    }

    if (backgroundExecutor != null) {
      backgroundExecutor.stopScanning();
      backgroundExecutor = null;
    }

    SharedPreferences prefs = getSharedPreferences(SHARED_PREFERENCES_NAME, Context.MODE_PRIVATE);
    prefs.edit().clear().apply();
  }

  public boolean canStopLocationService(boolean cancellationRequested) {
    if (cancellationRequested) {
      return listenerCount == 1;
    }
    return connectedEngines == 0;
  }

  public void flutterEngineConnected() {

    connectedEngines++;
    Log.d(TAG, "Flutter engine connected. Connected engine count " + connectedEngines);
  }

  public void flutterEngineDisconnected() {

    connectedEngines--;
    Log.d(TAG, "Flutter engine disconnected. Connected engine count " + connectedEngines);
  }

  public void startLocationService(
      boolean forceLocationManager,
      LocationOptions locationOptions,
      EventChannel.EventSink events) {

    listenerCount++;
    if (geolocationManager != null) {
      locationClient =
          geolocationManager.createLocationClient(
              this.getApplicationContext(),
              Boolean.TRUE.equals(forceLocationManager),
              locationOptions);

      geolocationManager.startPositionUpdates(
          locationClient,
          activity,
          (Location location) -> events.success(LocationMapper.toHashMap(location)),
          (ErrorCodes errorCodes) ->
              events.error(errorCodes.toString(), errorCodes.toDescription(), null));
    }
  }

  public void stopLocationService() {
    listenerCount--;
    Log.d(TAG, "Stopping location service.");
    if (locationClient != null && geolocationManager != null) {
      geolocationManager.stopPositionUpdates(locationClient);
    }
  }

  public void enableBackgroundMode(ForegroundNotificationOptions options) {
    if (backgroundNotification != null) {
      Log.d(TAG, "Service already in foreground mode.");
      changeNotificationOptions(options);
    } else {
      Log.d(TAG, "Start service in foreground mode.");

      backgroundNotification =
          new BackgroundNotification(
              this.getApplicationContext(), CHANNEL_ID, ONGOING_NOTIFICATION_ID, options);
      backgroundNotification.updateChannel(options.getNotificationChannelName());
      Notification notification = backgroundNotification.build();
      startForeground(ONGOING_NOTIFICATION_ID, notification);
      isForeground = true;
    }
    obtainWakeLocks(options);
  }

  @SuppressWarnings("deprecation")
  public void disableBackgroundMode() {
    if (isForeground) {
      Log.d(TAG, "Stop service in foreground.");
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        stopForeground(Service.STOP_FOREGROUND_REMOVE);
      } else {
        stopForeground(true);
      }
      releaseWakeLocks();
      isForeground = false;
      backgroundNotification = null;
    }
  }

  public void changeNotificationOptions(ForegroundNotificationOptions options) {
    if (backgroundNotification != null) {
      backgroundNotification.updateOptions(options, isForeground);
      obtainWakeLocks(options);
    }
  }

  public void setActivity(@Nullable Activity activity) {
    this.activity = activity;
  }

  public void setGeolocationManager(@Nullable GeolocationManager geolocationManager) {
      this.geolocationManager = geolocationManager;
  }

  private void releaseWakeLocks() {
    if (wakeLock != null && wakeLock.isHeld()) {
      wakeLock.release();
      wakeLock = null;
    }
    if (wifiLock != null && wifiLock.isHeld()) {
      wifiLock.release();
      wifiLock = null;
    }
  }

  @SuppressLint("WakelockTimeout")
  private void obtainWakeLocks(ForegroundNotificationOptions options) {
    releaseWakeLocks();
    if (options.isEnableWakeLock()) {
      PowerManager powerManager =
          (PowerManager) getApplicationContext().getSystemService(Context.POWER_SERVICE);
      if (powerManager != null) {
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKELOCK_TAG);
        wakeLock.setReferenceCounted(false);
        wakeLock.acquire();
      }
    }
    if (options.isEnableWifiLock()) {
      WifiManager wifiManager =
          (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
      if (wifiManager != null) {
        wifiLock = wifiManager.createWifiLock(getWifiLockType(), WIFILOCK_TAG);
        wifiLock.setReferenceCounted(false);
        wifiLock.acquire();
      }
    }
  }

  @SuppressWarnings("deprecation")
  private int getWifiLockType() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
      return WifiManager.WIFI_MODE_FULL_HIGH_PERF;
    }
    return WifiManager.WIFI_MODE_FULL_LOW_LATENCY;
  }

  class LocalBinder extends Binder {
    private final GeolocatorLocationService locationService;

    LocalBinder(GeolocatorLocationService locationService) {
      this.locationService = locationService;
    }

    public GeolocatorLocationService getLocationService() {
      return locationService;
    }
  }
}
