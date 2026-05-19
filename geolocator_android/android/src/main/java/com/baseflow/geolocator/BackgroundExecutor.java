package com.baseflow.geolocator;

import android.content.Context;
import android.content.res.AssetManager;
import android.location.Location;
import android.util.Log;

import androidx.annotation.NonNull;

import com.baseflow.geolocator.location.LocationMapper;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineGroup;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.FlutterCallbackInformation;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Manages the lifecycle of a headless FlutterEngine and handles communication with the background
 * isolate.
 */
public class BackgroundExecutor implements MethodChannel.MethodCallHandler {
  private static final String TAG = "BackgroundExecutor";
  private static final String BACKGROUND_CHANNEL_NAME = "flutter.baseflow.com/geolocator_android_background";

  private final AtomicBoolean isCallbackDispatcherReady = new AtomicBoolean(false);
  private MethodChannel backgroundChannel;
  private FlutterEngine backgroundEngine;
  private static FlutterEngineGroup engineGroup;

  /**
   * Starts the background isolate.
   *
   * @param context The application context.
   * @param dispatcherHandle The raw handle for the dispatcher callback.
   */
  public void startScanning(Context context, long dispatcherHandle) {
    if (backgroundEngine != null) {
      Log.i(TAG, "Background isolate already started.");
      return;
    }

    Log.i(TAG, "Starting background isolate...");

    if (engineGroup == null) {
      engineGroup = new FlutterEngineGroup(context);
    }

    FlutterCallbackInformation flutterCallbackInformation =
        FlutterCallbackInformation.lookupCallbackInformation(dispatcherHandle);
    if (flutterCallbackInformation == null) {
      Log.e(TAG, "Fatal: failed to find callback information for dispatcher.");
      return;
    }

    DartExecutor.DartEntrypoint entrypoint =
        new DartExecutor.DartEntrypoint(
            context.getPackageCodePath(),
            flutterCallbackInformation.callbackLibraryPath,
            flutterCallbackInformation.callbackName);

    backgroundEngine = engineGroup.createAndRunEngine(context, entrypoint);
    initializeMethodChannel(backgroundEngine.getDartExecutor());
  }

  /**
   * Stops the background isolate.
   */
  public void stopScanning() {
    if (backgroundEngine != null) {
      Log.i(TAG, "Stopping background isolate...");
      backgroundEngine.destroy();
      backgroundEngine = null;
      backgroundChannel = null;
      isCallbackDispatcherReady.set(false);
    }
  }

  /**
   * Returns whether the background isolate is running.
   */
  public boolean isRunning() {
    return backgroundEngine != null;
  }

  /**
   * Dispatches a location update to the background isolate.
   *
   * @param callbackHandle The raw handle for the user-provided callback.
   * @param location The location update.
   */
  public void onLocationUpdate(long callbackHandle, Location location) {
    if (!isCallbackDispatcherReady.get()) {
      Log.w(TAG, "Dropped location update because background isolate is not ready.");
      return;
    }

    Map<String, Object> arguments = new HashMap<>();
    arguments.put("callbackHandle", callbackHandle);
    arguments.put("position", LocationMapper.toHashMap(location));

    backgroundChannel.invokeMethod("onLocationUpdate", arguments);
  }

  private void initializeMethodChannel(BinaryMessenger messenger) {
    backgroundChannel = new MethodChannel(messenger, BACKGROUND_CHANNEL_NAME);
    backgroundChannel.setMethodCallHandler(this);
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
    if (call.method.equals("initialized")) {
      isCallbackDispatcherReady.set(true);
      result.success(true);
    } else {
      result.notImplemented();
    }
  }
}
