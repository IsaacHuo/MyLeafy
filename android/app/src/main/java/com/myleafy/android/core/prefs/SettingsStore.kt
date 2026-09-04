package com.myleafy.android.core.prefs

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.settingsDataStore by preferencesDataStore(name = "myleafy_settings")

/** 非敏感应用偏好（对应 iOS UserDefaults 的 campus 作用域键）。 */
data class Settings(
    val campusId: String = "bjfu",
    val eduId: String? = null,
    val themeColor: String = "green",
    val themeMode: String = "system",
    val textScale: String = "system",
    val language: String = "system",
    val hideWeekends: Boolean = false,
    val timetableBackground: TimetableBackgroundSettings = TimetableBackgroundSettings(),
)

data class TimetableBackgroundSettings(
    val enabled: Boolean = false,
    val kind: String = "color",
    val photoPath: String? = null,
    val blurredPhotoPath: String? = null,
    val colorHex: String = "#DDE9DF",
    val contentScale: String = "crop",
    val visibilityPercent: Int = 55,
    val blurRadius: Int = 0,
    val overlayPercent: Int = 30,
    val courseOpacityPercent: Int = 92,
)

/**
 * 应用设置存储（DataStore Preferences）。
 * 敏感数据（凭据、教务 Cookie）走 `SecureStorage`，不在此存储。
 */
class SettingsStore(private val context: Context) {

    val settings: Flow<Settings> = context.settingsDataStore.data.map { prefs ->
        Settings(
            campusId = prefs[Keys.CAMPUS_ID] ?: DEFAULT_CAMPUS_ID,
            eduId = prefs[Keys.EDU_ID],
            themeColor = prefs[Keys.THEME_COLOR] ?: "green",
            themeMode = prefs[Keys.THEME_MODE] ?: "system",
            textScale = prefs[Keys.TEXT_SCALE] ?: "system",
            language = prefs[Keys.LANGUAGE] ?: "system",
            hideWeekends = prefs[Keys.HIDE_WEEKENDS] ?: false,
            timetableBackground = TimetableBackgroundSettings(
                enabled = prefs[Keys.BACKGROUND_ENABLED] ?: false,
                kind = prefs[Keys.BACKGROUND_KIND] ?: "color",
                photoPath = prefs[Keys.BACKGROUND_PHOTO_PATH],
                blurredPhotoPath = prefs[Keys.BACKGROUND_BLURRED_PHOTO_PATH],
                colorHex = prefs[Keys.BACKGROUND_COLOR_HEX] ?: "#DDE9DF",
                contentScale = prefs[Keys.BACKGROUND_CONTENT_SCALE] ?: "crop",
                visibilityPercent = prefs[Keys.BACKGROUND_VISIBILITY] ?: 55,
                blurRadius = prefs[Keys.BACKGROUND_BLUR] ?: 0,
                overlayPercent = prefs[Keys.BACKGROUND_OVERLAY] ?: 30,
                courseOpacityPercent = prefs[Keys.BACKGROUND_COURSE_OPACITY] ?: 92,
            ),
        )
    }

    suspend fun setCampus(campusId: String, eduId: String?) {
        context.settingsDataStore.edit { prefs ->
            prefs[Keys.CAMPUS_ID] = campusId
            if (eduId.isNullOrBlank()) prefs.remove(Keys.EDU_ID) else prefs[Keys.EDU_ID] = eduId
        }
    }

    suspend fun setThemeColor(themeColor: String) {
        context.settingsDataStore.edit { prefs -> prefs[Keys.THEME_COLOR] = themeColor }
    }

    suspend fun setThemeMode(themeMode: String) {
        require(themeMode in setOf("system", "light", "dark")) { "Unsupported theme mode" }
        context.settingsDataStore.edit { prefs -> prefs[Keys.THEME_MODE] = themeMode }
    }

    suspend fun setTextScale(textScale: String) {
        require(textScale in setOf("system", "large")) { "Unsupported text scale" }
        context.settingsDataStore.edit { prefs -> prefs[Keys.TEXT_SCALE] = textScale }
    }

    suspend fun setLanguage(language: String) {
        context.settingsDataStore.edit { prefs -> prefs[Keys.LANGUAGE] = language }
    }

    suspend fun setHideWeekends(hideWeekends: Boolean) {
        context.settingsDataStore.edit { prefs -> prefs[Keys.HIDE_WEEKENDS] = hideWeekends }
    }

    suspend fun setTimetableBackground(value: TimetableBackgroundSettings) {
        context.settingsDataStore.edit { prefs ->
            prefs[Keys.BACKGROUND_ENABLED] = value.enabled
            prefs[Keys.BACKGROUND_KIND] = value.kind
            value.photoPath?.let { prefs[Keys.BACKGROUND_PHOTO_PATH] = it }
                ?: prefs.remove(Keys.BACKGROUND_PHOTO_PATH)
            value.blurredPhotoPath?.let { prefs[Keys.BACKGROUND_BLURRED_PHOTO_PATH] = it }
                ?: prefs.remove(Keys.BACKGROUND_BLURRED_PHOTO_PATH)
            prefs[Keys.BACKGROUND_COLOR_HEX] = value.colorHex
            prefs[Keys.BACKGROUND_CONTENT_SCALE] = value.contentScale
            prefs[Keys.BACKGROUND_VISIBILITY] = value.visibilityPercent.coerceIn(0, 100)
            prefs[Keys.BACKGROUND_BLUR] = value.blurRadius.coerceIn(0, 25)
            prefs[Keys.BACKGROUND_OVERLAY] = value.overlayPercent.coerceIn(0, 100)
            prefs[Keys.BACKGROUND_COURSE_OPACITY] = value.courseOpacityPercent.coerceIn(35, 100)
        }
    }

    suspend fun clearIdentity() {
        context.settingsDataStore.edit { prefs ->
            prefs.remove(Keys.EDU_ID)
        }
    }

    private object Keys {
        val CAMPUS_ID = stringPreferencesKey("campus_id")
        val EDU_ID = stringPreferencesKey("edu_id")
        val THEME_COLOR = stringPreferencesKey("theme_color")
        val THEME_MODE = stringPreferencesKey("theme_mode")
        val TEXT_SCALE = stringPreferencesKey("text_scale")
        val LANGUAGE = stringPreferencesKey("language")
        val HIDE_WEEKENDS = booleanPreferencesKey("hide_weekends")
        val BACKGROUND_ENABLED = booleanPreferencesKey("timetable_background_enabled")
        val BACKGROUND_KIND = stringPreferencesKey("timetable_background_kind")
        val BACKGROUND_PHOTO_PATH = stringPreferencesKey("timetable_background_photo_path")
        val BACKGROUND_BLURRED_PHOTO_PATH = stringPreferencesKey("timetable_background_blurred_photo_path")
        val BACKGROUND_COLOR_HEX = stringPreferencesKey("timetable_background_color_hex")
        val BACKGROUND_CONTENT_SCALE = stringPreferencesKey("timetable_background_content_scale")
        val BACKGROUND_VISIBILITY = intPreferencesKey("timetable_background_visibility")
        val BACKGROUND_BLUR = intPreferencesKey("timetable_background_blur")
        val BACKGROUND_OVERLAY = intPreferencesKey("timetable_background_overlay")
        val BACKGROUND_COURSE_OPACITY = intPreferencesKey("timetable_background_course_opacity")
    }

    private companion object {
        const val DEFAULT_CAMPUS_ID = "bjfu"
    }
}
