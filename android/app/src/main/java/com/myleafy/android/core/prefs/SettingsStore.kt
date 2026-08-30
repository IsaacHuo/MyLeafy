package com.myleafy.android.core.prefs

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
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
    }

    private companion object {
        const val DEFAULT_CAMPUS_ID = "bjfu"
    }
}
