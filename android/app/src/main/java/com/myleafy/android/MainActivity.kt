package com.myleafy.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.myleafy.android.core.prefs.Settings
import com.myleafy.android.ui.MyLeafyApp
import com.myleafy.android.ui.theme.MyLeafyTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val settings by (application as MyLeafyApplication).container.settingsStore.settings
                .collectAsStateWithLifecycle(initialValue = Settings())
            val darkTheme = when (settings.themeMode) {
                "light" -> false
                "dark" -> true
                else -> isSystemInDarkTheme()
            }
            val systemDensity = LocalDensity.current
            val preferredDensity = Density(
                density = systemDensity.density,
                fontScale = systemDensity.fontScale * if (settings.textScale == "large") 1.15f else 1f,
            )
            CompositionLocalProvider(LocalDensity provides preferredDensity) {
                MyLeafyTheme(darkTheme = darkTheme) {
                    MyLeafyApp(deepLinkIntent = intent)
                }
            }
        }
    }
}
