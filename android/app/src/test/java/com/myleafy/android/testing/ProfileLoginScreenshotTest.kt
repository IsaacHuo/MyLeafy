package com.myleafy.android.testing

import android.app.Application
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.width
import com.github.takahirom.roborazzi.captureRoboImage
import com.myleafy.android.features.auth.LoginContent
import com.myleafy.android.features.auth.LoginUiState
import com.myleafy.android.features.profile.ProfileContent
import com.myleafy.android.features.profile.ProfileUiState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.experimental.categories.Category
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * 我的 and 学校登录 goldens, driven through the stateless `ProfileContent` /
 * `LoginContent` entry points. No ViewModel, DI container, account, captcha request
 * or network call is involved.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w360dp-h800dp-xxhdpi", application = Application::class)
@Category(ScreenshotTests::class)
class ProfileLoginScreenshotTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun profileLocalLight() {
        renderProfile(ProfileUiState.Local(campusId = "bjfu", eduId = null))
        capture()
    }

    @Test
    fun profileCommunityDark() {
        renderProfile(
            state = ProfileUiState.Community("bjfu", "20240101", profileFixture()),
            darkTheme = true,
        )
        capture()
    }

    @Test
    fun profileErrorLongMessage() {
        renderProfile(
            state = ProfileUiState.Error("bjfu", "20240101", ScreenshotData.LONG_ERROR_MESSAGE),
        )
        composeRule
            .onNodeWithText(ScreenshotData.LONG_ERROR_MESSAGE, useUnmergedTree = true)
            .assertTextLayoutFits()
        capture()
    }

    /**
     * 840dp + 200% font: the content column stays centred and capped, the last
     * destructive action is still reachable, and its confirmation dialog opens.
     */
    @Test
    @Config(sdk = [36], qualifiers = "w840dp-h900dp-xxhdpi", application = Application::class)
    fun profileWide840FontScale200LogoutReachable() {
        var logoutCalls = 0
        renderProfile(
            state = ProfileUiState.Community("bjfu", "20240101", profileFixture()),
            fontScale = 2f,
            onLogout = { logoutCalls += 1 },
        )

        composeRule.onNode(hasScrollAction()).performScrollToNode(hasText("退出登录"))
        composeRule.onNodeWithText("退出登录").assertIsDisplayed().performClick()
        composeRule.onNodeWithText("将清理学校和社区会话及本机保存的登录凭据；课表、日程、随记和学业缓存会按当前身份保留。")
            .assertIsDisplayed()
        capture()

        composeRule.onNodeWithText("退出").performClick()
        composeRule.runOnIdle { assertEquals(1, logoutCalls) }
    }

    @Test
    fun loginEmptyLight() {
        renderLogin(state = LoginUiState())
        capture()
    }

    @Test
    fun loginSubmittingDark() {
        renderLogin(
            state = LoginUiState(isSubmitting = true),
            account = "20240101",
            password = "leafy-password",
            captcha = "8F2K",
            darkTheme = true,
        )
        capture()
    }

    /**
     * 200% font + long error: the submit action must stay reachable by scrolling,
     * stay clickable, and the error text must wrap instead of being clipped.
     */
    @Test
    fun loginLongErrorFontScale200Reachability() {
        var submitCalls = 0
        renderLogin(
            state = LoginUiState(loginErrorMessage = ScreenshotData.LONG_ERROR_MESSAGE),
            account = "20240101",
            password = "leafy-password",
            captcha = "8F2K",
            fontScale = 2f,
            onSubmit = { submitCalls += 1 },
        )

        composeRule
            .onNodeWithText(ScreenshotData.LONG_ERROR_MESSAGE, useUnmergedTree = true)
            .assertTextLayoutFits()
        composeRule.onNode(hasScrollAction()).performScrollToNode(hasText("登录"))
        composeRule.onNodeWithText("登录").assertIsDisplayed().performClick()
        composeRule.runOnIdle { assertEquals(1, submitCalls) }
        capture()
    }

    /** The form keeps its 420dp cap on a wide window instead of stretching. */
    @Test
    @Config(sdk = [36], qualifiers = "w840dp-h900dp-xxhdpi", application = Application::class)
    fun loginWide840KeepsFormWidth() {
        renderLogin(state = LoginUiState(), account = "20240101")
        val formWidth = composeRule
            .onAllNodes(hasSetTextAction())
            .onFirst()
            .getUnclippedBoundsInRoot()
            .width
        assertTrue("Form field width $formWidth exceeds the 420dp cap", formWidth <= 420.dp)
        capture()
    }

    private fun renderProfile(
        state: ProfileUiState,
        isSigningOut: Boolean = false,
        darkTheme: Boolean = false,
        fontScale: Float = 1f,
        onLogout: () -> Unit = {},
    ) {
        composeRule.setContent {
            LeafyScreenshotTheme(darkTheme = darkTheme, fontScale = fontScale) {
                ProfileContent(
                    state = state,
                    isSigningOut = isSigningOut,
                    onLoginClick = {},
                    onEditProfileClick = {},
                    onFeatureClick = {},
                    onLogout = onLogout,
                )
            }
        }
        composeRule.waitForIdle()
    }

    private fun renderLogin(
        state: LoginUiState,
        account: String = "",
        password: String = "",
        captcha: String = "",
        darkTheme: Boolean = false,
        fontScale: Float = 1f,
        onSubmit: () -> Unit = {},
    ) {
        composeRule.setContent {
            LeafyScreenshotTheme(darkTheme = darkTheme, fontScale = fontScale) {
                LoginContent(
                    state = state,
                    account = account,
                    password = password,
                    captcha = captcha,
                    onAccountChange = {},
                    onPasswordChange = {},
                    onCaptchaChange = {},
                    onSubmit = onSubmit,
                    onRefreshCaptcha = {},
                    onBack = {},
                )
            }
        }
        composeRule.waitForIdle()
    }

    private fun capture() = composeRule.onRoot().captureRoboImage()
}
