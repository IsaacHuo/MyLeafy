package com.myleafy.android.core.campus

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CampusModelsTest {

    @Test
    fun bjfuSupportsAllCapabilities() {
        assertTrue(CampusDescriptor.bjfu.supports(CampusCapabilities.COMMUNITY))
        assertTrue(CampusDescriptor.bjfu.supports(CampusCapabilities.TIMETABLE))
        assertTrue(CampusDescriptor.bjfu.supports(CampusCapabilities.WEATHER))
    }

    @Test
    fun customCampusDoesNotSupportWeather() {
        assertFalse(CampusDescriptor.custom.supports(CampusCapabilities.WEATHER))
        assertFalse(CampusDescriptor.custom.supports(CampusCapabilities.CLASSROOMS))
    }

    @Test
    fun campusIdMustBeLowercase() {
        assertEquals("bjfu", CampusID.bjfu.rawValue)
    }
}
