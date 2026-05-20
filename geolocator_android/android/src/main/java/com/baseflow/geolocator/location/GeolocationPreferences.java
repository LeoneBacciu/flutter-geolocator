package com.baseflow.geolocator.location;

import android.content.Context;
import android.content.SharedPreferences;
import androidx.annotation.Nullable;

public class GeolocationPreferences {
    private static final String SHARED_PREFERENCES_NAME = "geolocator_background_preferences";
    private static final String CALLBACK_HANDLE_KEY = "callback_handle";
    private static final String DISPATCHER_HANDLE_KEY = "dispatcher_handle";
    private static final String TIME_INTERVAL_KEY = "time_interval";
    private static final String DISTANCE_FILTER_KEY = "distance_filter";

    // Foreground keys
    private static final String FOREGROUND_TITLE_KEY = "fg_title";
    private static final String FOREGROUND_TEXT_KEY = "fg_text";
    private static final String FOREGROUND_CHANNEL_NAME_KEY = "fg_channel";
    private static final String FOREGROUND_ICON_NAME_KEY = "fg_icon_name";
    private static final String FOREGROUND_ICON_TYPE_KEY = "fg_icon_type";
    private static final String FOREGROUND_ENABLE_WIFI_LOCK_KEY = "fg_enable_wifi_lock";
    private static final String FOREGROUND_ENABLE_WAKE_LOCK_KEY = "fg_enable_wake_lock";
    private static final String FOREGROUND_SET_ONGOING_KEY = "fg_set_ongoing";
    private static final String FOREGROUND_COLOR_KEY = "fg_color";

    private final SharedPreferences preferences;

    public GeolocationPreferences(Context context) {
        this.preferences = context.getSharedPreferences(SHARED_PREFERENCES_NAME, Context.MODE_PRIVATE);
    }

    public void saveBackgroundSettings(BackgroundSettings settings) {
        preferences.edit()
                .putLong(CALLBACK_HANDLE_KEY, settings.getCallbackHandle())
                .putLong(DISPATCHER_HANDLE_KEY, settings.getDispatcherHandle())
                .putLong(TIME_INTERVAL_KEY, settings.getTimeInterval())
                .putLong(DISTANCE_FILTER_KEY, settings.getDistanceFilter())
                .apply();
    }

    public void clearBackgroundSettings() {
        preferences.edit().clear().apply();
    }

    @Nullable
    public BackgroundSettings getBackgroundSettings() {
        long callbackHandle = preferences.getLong(CALLBACK_HANDLE_KEY, 0);
        long dispatcherHandle = preferences.getLong(DISPATCHER_HANDLE_KEY, 0);
        if (callbackHandle == 0 || dispatcherHandle == 0) return null;

        return new BackgroundSettings(
                callbackHandle,
                dispatcherHandle,
                preferences.getLong(TIME_INTERVAL_KEY, 0),
                preferences.getLong(DISTANCE_FILTER_KEY, 0)
        );
    }

    public void saveForegroundNotificationOptions(ForegroundNotificationOptions options) {
        preferences.edit()
                .putString(FOREGROUND_TITLE_KEY, options.getNotificationTitle())
                .putString(FOREGROUND_TEXT_KEY, options.getNotificationText())
                .putString(FOREGROUND_CHANNEL_NAME_KEY, options.getNotificationChannelName())
                .putString(FOREGROUND_ICON_NAME_KEY, options.getNotificationIcon().getName())
                .putString(FOREGROUND_ICON_TYPE_KEY, options.getNotificationIcon().getDefType())
                .putBoolean(FOREGROUND_ENABLE_WIFI_LOCK_KEY, options.isEnableWifiLock())
                .putBoolean(FOREGROUND_ENABLE_WAKE_LOCK_KEY, options.isEnableWakeLock())
                .putBoolean(FOREGROUND_SET_ONGOING_KEY, options.isSetOngoing())
                .putInt(FOREGROUND_COLOR_KEY, options.getColor() != null ? options.getColor() : -1)
                .apply();
    }

    @Nullable
    public ForegroundNotificationOptions getForegroundNotificationOptions() {
        String title = preferences.getString(FOREGROUND_TITLE_KEY, null);
        if (title == null) return null;

        String iconName = preferences.getString(FOREGROUND_ICON_NAME_KEY, "");
        String iconType = preferences.getString(FOREGROUND_ICON_TYPE_KEY, "");
        AndroidIconResource icon = new AndroidIconResource(iconName, iconType);

        int color = preferences.getInt(FOREGROUND_COLOR_KEY, -1);

        return new ForegroundNotificationOptions(
                title,
                preferences.getString(FOREGROUND_TEXT_KEY, ""),
                preferences.getString(FOREGROUND_CHANNEL_NAME_KEY, ""),
                icon,
                preferences.getBoolean(FOREGROUND_ENABLE_WIFI_LOCK_KEY, false),
                preferences.getBoolean(FOREGROUND_ENABLE_WAKE_LOCK_KEY, false),
                preferences.getBoolean(FOREGROUND_SET_ONGOING_KEY, false),
                color == -1 ? null : color
        );
    }
}
