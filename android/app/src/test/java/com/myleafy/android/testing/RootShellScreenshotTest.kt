package com.myleafy.android.testing

import android.app.Application
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.background
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.github.takahirom.roborazzi.captureRoboImage
import com.myleafy.android.features.profile.*
import com.myleafy.android.features.community.*
import com.myleafy.android.navigation.*
import org.junit.Rule
import org.junit.Test
import org.junit.experimental.categories.Category
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h800dp-xxhdpi", application = Application::class)
@Category(ScreenshotTests::class)
class RootShellScreenshotTest {
    @get:Rule val composeRule = createComposeRule()

    @Test fun profileCompactLight() = profile()
    @Test fun profileCompactDark() = profile(dark = true)
    @Test fun profileLargeText() = profile(fontScale = 2f)
    @Test @Config(qualifiers = "w600dp-h900dp-xxhdpi") fun profileRail600() = profile()
    @Test @Config(qualifiers = "w840dp-h900dp-xxhdpi") fun profileRail840Dark() = profile(dark = true)

    @Test fun communityCompactLight() {
        composeRule.setContent {
            LeafyScreenshotTheme {
                LeafyNavigationScaffold(RootTab.COMMUNITY, {}) {
                    CommunityContent(
                        state = CommunityUiState(posts = listOf(postFixture(id = "shell", title = "校园里的小发现", category = "校园生活")), isInitialLoading = false),
                        onPostClick = {}, onComposeClick = {}, onSearchClick = {}, onNotificationsClick = {},
                        onRefresh = {}, onSelectHot = {}, onSelectLatest = {},
                    )
                }
            }
        }
        composeRule.onNodeWithTag("root-tab-community").assertIsSelected()
        composeRule.onRoot().captureRoboImage()
    }

    private fun profile(dark: Boolean = false, fontScale: Float = 1f) {
        composeRule.setContent {
            LeafyScreenshotTheme(darkTheme = dark, fontScale = fontScale) {
                // A dark window behind the shell must never leak around the floating navigation.
                Box(Modifier.fillMaxSize().background(Color.Black)) {
                    LeafyNavigationScaffold(RootTab.PROFILE, {}) {
                        ProfileContent(
                            state = ProfileUiState.Community("bjfu", "20240101", profileFixture()),
                            isSigningOut = false, onLoginClick = {}, onEditProfileClick = {},
                            onFeatureClick = {}, onLogout = {},
                        )
                    }
                }
            }
        }
        RootTab.entries.forEach { composeRule.onNodeWithTag("root-tab-${it.route}").assertIsDisplayed() }
        composeRule.onNodeWithTag("root-tab-profile").assertIsSelected()
        composeRule.onRoot().captureRoboImage()
    }
}
