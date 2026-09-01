package com.myleafy.android.ui.components

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.material3.Text
import com.myleafy.android.ui.theme.MyLeafyTheme
import org.junit.Rule
import org.junit.Test

class LeafyComponentsTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun clickableSharedComponentsMeetMinimumTouchTarget() {
        composeRule.setContent {
            MyLeafyTheme(darkTheme = false) {
                androidx.compose.foundation.layout.Column {
                    LeafyActionIconButton(
                        onClick = {},
                        modifier = Modifier.testTag("icon-action"),
                    ) { Text("+") }
                    LeafySettingsRow(
                        headlineContent = { Text("设置项") },
                        onClick = {},
                        modifier = Modifier.testTag("settings-row"),
                    )
                    LeafyToolRow(
                        headlineContent = { Text("工具项") },
                        onClick = {},
                        modifier = Modifier.testTag("tool-row"),
                    )
                }
            }
        }

        composeRule.onNodeWithTag("icon-action")
            .assertWidthIsAtLeast(48.dp)
            .assertHeightIsAtLeast(48.dp)
        composeRule.onNodeWithTag("settings-row").assertHeightIsAtLeast(48.dp)
        composeRule.onNodeWithTag("tool-row").assertHeightIsAtLeast(48.dp)
    }

    @Test
    fun sharedStatesRemainReadableInDarkThemeAtLargeFontScale() {
        composeRule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale = 1.3f)) {
                MyLeafyTheme(darkTheme = true) {
                    LeafyEmptyState(
                        title = "暂无内容",
                        message = "稍后再来看看，页面会保留清晰的状态说明。",
                    )
                }
            }
        }

        composeRule.onNodeWithText("暂无内容").assertIsDisplayed()
        composeRule.onNodeWithText("稍后再来看看，页面会保留清晰的状态说明。").assertIsDisplayed()
    }
}
