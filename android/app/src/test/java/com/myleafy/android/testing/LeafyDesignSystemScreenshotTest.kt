package com.myleafy.android.testing

import android.app.Application
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.Density
import com.github.takahirom.roborazzi.captureRoboImage
import com.myleafy.android.ui.components.LeafyEmptyState
import com.myleafy.android.ui.components.LeafyPrimaryButton
import com.myleafy.android.ui.components.LeafySecondaryButton
import com.myleafy.android.ui.components.LeafySettingsDivider
import com.myleafy.android.ui.components.LeafySettingsGroup
import com.myleafy.android.ui.components.LeafySettingsRow
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.MyLeafyTheme
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
class LeafyDesignSystemScreenshotTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test fun componentsLight() = capture(darkTheme = false, fontScale = 1f)

    @Test fun componentsDark() = capture(darkTheme = true, fontScale = 1f)

    @Test fun componentsFontScale130() = capture(darkTheme = false, fontScale = 1.3f)

    @Test fun componentsFontScale200() = capture(darkTheme = false, fontScale = 2f)

    private fun capture(darkTheme: Boolean, fontScale: Float) {
        composeRule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
                MyLeafyTheme(darkTheme = darkTheme) {
                    Surface(
                        modifier = Modifier.fillMaxSize(),
                        color = MaterialTheme.colorScheme.background,
                    ) {
                        Column(
                            modifier = Modifier.verticalScroll(rememberScrollState()).padding(LeafySpacing.page),
                            verticalArrangement = Arrangement.spacedBy(LeafySpacing.compact),
                        ) {
                            Text("MyLeafy Design System", style = MaterialTheme.typography.headlineSmall)
                            LeafyPrimaryButton(onClick = {}, modifier = Modifier.fillMaxWidth()) { Text("主要操作") }
                            LeafySecondaryButton(onClick = {}, modifier = Modifier.fillMaxWidth()) { Text("次要操作") }
                            LeafyStatusBanner(message = "课程数据已同步", isError = false)
                            LeafyStatusBanner(message = "刷新失败，已保留上次内容", isError = true)
                            LeafySettingsGroup(title = "设置分组") {
                                LeafySettingsRow(
                                    headlineContent = { Text("课程提醒") },
                                    supportingContent = { Text("上课前 30 分钟通知") },
                                )
                                LeafySettingsDivider()
                                LeafySettingsRow(headlineContent = { Text("深色模式") })
                            }
                            LeafyEmptyState(
                                title = "还没有日程",
                                message = "添加第一项个人日程后，会在这里显示。",
                                icon = Icons.Outlined.CalendarMonth,
                            )
                        }
                    }
                }
            }
        }
        composeRule.waitForIdle()
        composeRule.onRoot().captureRoboImage()
    }
}
