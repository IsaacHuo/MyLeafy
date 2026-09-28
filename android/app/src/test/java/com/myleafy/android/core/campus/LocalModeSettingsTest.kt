package com.myleafy.android.core.campus

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import com.myleafy.android.core.prefs.SettingsStore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [36], application = Application::class)
class LocalModeSettingsTest {
    @Test
    fun localChoiceSurvivesARecreatedStoreAndClearsTheSchoolId() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Application>()
        val store = SettingsStore(context)
        store.setCampus("bjfu", "20260001")
        store.setCampus("guest", null)
        val restored = SettingsStore(context).settings.first()
        assertEquals("guest", restored.campusId)
        assertNull(restored.eduId)
        store.setCampus("bjfu", "20260002")
        assertEquals("20260002", SettingsStore(context).settings.first().eduId)
    }
}
