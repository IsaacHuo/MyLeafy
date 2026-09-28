package com.myleafy.android

import android.os.Bundle
import android.content.Intent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.SystemBarStyle
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.myleafy.android.core.prefs.Settings
import com.myleafy.android.ui.MyLeafyApp
import com.myleafy.android.ui.theme.MyLeafyTheme
import kotlinx.coroutines.flow.MutableStateFlow

class MainActivity : ComponentActivity() {
    private val incomingIntent = MutableStateFlow<Intent?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        incomingIntent.value = intent
        enableEdgeToEdge()
        setContent {
            val navigationIntent by incomingIntent.collectAsStateWithLifecycle()
            val settings by (application as MyLeafyApplication).container.settingsStore.settings
                .collectAsStateWithLifecycle(initialValue = Settings())
            val darkTheme = when (settings.themeMode) {
                "light" -> false
                "dark" -> true
                else -> isSystemInDarkTheme()
            }
            SideEffect {
                val systemBarStyle = if (darkTheme) {
                    SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
                } else {
                    SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT)
                }
                enableEdgeToEdge(statusBarStyle = systemBarStyle, navigationBarStyle = systemBarStyle)
                window.isNavigationBarContrastEnforced = false
                androidx.core.view.WindowCompat.getInsetsController(window, window.decorView).apply {
                    isAppearanceLightStatusBars = !darkTheme
                    isAppearanceLightNavigationBars = !darkTheme
                }
            }
            val systemDensity = LocalDensity.current
            val preferredDensity = Density(
                density = systemDensity.density,
                fontScale = systemDensity.fontScale * if (settings.textScale == "large") 1.15f else 1f,
            )
            CompositionLocalProvider(LocalDensity provides preferredDensity) {
                MyLeafyTheme(darkTheme = darkTheme) {
                    Surface(
                        modifier = Modifier.fillMaxSize(),
                        color = MaterialTheme.colorScheme.background,
                    ) {
                        MyLeafyApp(deepLinkIntent = navigationIntent)
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        incomingIntent.value = intent
    }
}
