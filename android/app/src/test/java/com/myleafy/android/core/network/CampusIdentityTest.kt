package com.myleafy.android.core.network

import com.myleafy.android.core.campus.CampusID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class CampusIdentityTest {

    @Test
    fun scopeKeyIsStableForSameIdentity() {
        val identity = CampusIdentity(
            campusId = CampusID.bjfu,
            eduId = "2012345678",
            displayName = null,
            portal = SchoolPortal.UNDERGRADUATE,
            kind = CampusIdentity.IdentityKind.SCHOOL_PORTAL,
        )
        assertEquals(identity.scopeKey, identity.scopeKey)
    }

    @Test
    fun scopeKeyDiffersByEduId() {
        val a = identity("2012345678")
        val b = identity("2012345679")
        assertNotEquals(a.scopeKey, b.scopeKey)
    }

    @Test
    fun scopeKeyNormalizesEduIdCase() {
        val upper = identity("2012345678").copy(eduId = "2012345678")
        val mixed = identity("2012345678").copy(eduId = "2012345678")
        assertEquals(upper.scopeKey, mixed.scopeKey)
    }

    private fun identity(eduId: String) = CampusIdentity(
        campusId = CampusID.bjfu,
        eduId = eduId,
        displayName = null,
        portal = SchoolPortal.UNDERGRADUATE,
        kind = CampusIdentity.IdentityKind.SCHOOL_PORTAL,
    )
}
