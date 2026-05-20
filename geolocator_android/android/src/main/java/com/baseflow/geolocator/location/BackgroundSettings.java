package com.baseflow.geolocator.location;

import androidx.annotation.NonNull;
import java.util.Map;

public class BackgroundSettings {
    private final long callbackHandle;
    private final long dispatcherHandle;
    private final long timeInterval;
    private final long distanceFilter;

    public BackgroundSettings(long callbackHandle, long dispatcherHandle, long timeInterval, long distanceFilter) {
        this.callbackHandle = callbackHandle;
        this.dispatcherHandle = dispatcherHandle;
        this.timeInterval = timeInterval;
        this.distanceFilter = distanceFilter;
    }

    @SuppressWarnings("DataFlowIssue")
    public static BackgroundSettings parseArguments(@NonNull Map<String, Object> arguments) {
        long callbackHandle = ((Number) arguments.get("callbackHandle")).longValue();
        long dispatcherHandle = ((Number) arguments.get("dispatcherHandle")).longValue();
        long timeInterval = ((Number) arguments.get("intervalDuration")).longValue();
        long distanceFilter = ((Number) arguments.get("distanceFilter")).longValue();

        return new BackgroundSettings(callbackHandle, dispatcherHandle, timeInterval, distanceFilter);
    }

    public long getCallbackHandle() { return callbackHandle; }
    public long getDispatcherHandle() { return dispatcherHandle; }
    public long getTimeInterval() { return timeInterval; }
    public long getDistanceFilter() { return distanceFilter; }
}
