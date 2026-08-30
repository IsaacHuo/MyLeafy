package com.myleafy.android.core.campus

import com.myleafy.android.core.network.CampusIdentity
import com.myleafy.android.core.network.SchoolPortal
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ActiveAppScopeStoreTest {
    @Test
    fun schoolIdentityActivatesItsCapabilitiesAndStableScope() {
        val identity = CampusIdentity(
            campusId = CampusID.bjfu,
            eduId = "20260001",
            displayName = null,
            portal = SchoolPortal.UNDERGRADUATE,
            kind = CampusIdentity.IdentityKind.SCHOOL_PORTAL,
        )
        val store = ActiveAppScopeStore()

        store.activate(identity)

        assertEquals(identity.scopeKey, store.current.scopeKey)
        assertEquals("20260001", store.current.eduId)
        assertTrue(store.current.supports(CampusCapabilities.COMMUNITY))
        assertFalse(store.current.isGuest)
    }

    @Test
    fun guestNeverReceivesCommunityCapability() {
        val store = ActiveAppScopeStore()

        store.activateGuest("guest-device-scope")

        assertTrue(store.current.isGuest)
        assertTrue(store.current.supports(CampusCapabilities.TIMETABLE))
        assertFalse(store.current.supports(CampusCapabilities.COMMUNITY))
    }
}
