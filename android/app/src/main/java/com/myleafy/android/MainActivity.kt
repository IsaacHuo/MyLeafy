package com.myleafy.android

import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.Lifecycle
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.CancellationException
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
        val container = (application as MyLeafyApplication).container
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.RESUMED) {
                container.activeAppScopeStore.scope.collectLatest { scope ->
                    if (scope.isGuest || scope.eduId == null) return@collectLatest
                    while (true) {
                        try { container.foregroundActivity.record(scope.scopeKey) }
                        catch (cancelled: CancellationException) { throw cancelled }
                        catch (failure: Exception) { android.util.Log.e("AppActivity", "Foreground activity retained for retry", failure) }
                        delay(300_000)
                    }
                }
            }
        }
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
                        MyLeafyApp(deepLinkIntent = navigationIntent, timetableBackground = settings.timetableBackground)
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

    override fun onResume() {
        super.onResume()
        (application as MyLeafyApplication).container.appUpdateManager.check(manual = false)
    }
}
