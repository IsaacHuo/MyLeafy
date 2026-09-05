package com.myleafy.android.testing

import android.app.Application
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import com.github.takahirom.roborazzi.captureRoboImage
import com.myleafy.android.features.campus.CampusDashboard
import com.myleafy.android.features.campus.CampusSyncState
import com.myleafy.android.features.campus.CampusUiState
import com.myleafy.android.features.schedule.ScheduleContent
import com.myleafy.android.features.schedule.ScheduleSection
import com.myleafy.android.features.schedule.notifications.ScheduleReportsUiState
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
class RootContentScreenshotTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test fun scheduleEmptyLight() {
        composeRule.setContent {
            MyLeafyTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    ScheduleContent(
                        section = ScheduleSection.EVENTS,
                        memos = emptyList(),
                        events = emptyList(),
                        onNewMemo = {}, onMemoClick = {}, onNewEvent = {}, onEventClick = {},
                        onFeatureClick = {}, reportsState = ScheduleReportsUiState(),
                        notificationPermissionDenied = false, onToggleReport = { _, _ -> },
                        onSetEventReminder = { _, _, _ -> },
                    )
                }
            }
        }
        composeRule.waitForIdle()
        composeRule.onRoot().captureRoboImage()
    }

    @Test fun campusCompactLight() = captureCampus()

    @Test
    @Config(sdk = [36], qualifiers = "w700dp-h900dp-xxhdpi", application = Application::class)
    fun campusMediumLight() = captureCampus()

    private fun captureCampus() {
        composeRule.setContent {
            MyLeafyTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    CampusDashboard(
                        state = CampusUiState.Loaded(emptyList(), emptyList(), emptyList(), null, emptyList()),
                        syncState = CampusSyncState.Idle,
                        onConsumeSync = {}, onGradesClick = {}, onExamsClick = {}, onClassroomClick = {},
                        onFeatureClick = {}, modifier = Modifier.fillMaxSize(),
                    )
                }
            }
        }
        composeRule.waitForIdle()
        composeRule.onRoot().captureRoboImage()
    }
}
