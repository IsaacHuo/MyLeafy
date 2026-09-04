package com.myleafy.android.services.supabase

import org.junit.Assert.assertEquals
import org.junit.Test

class TimetableSharingServiceTest {
    @Test
    fun inviteCodeNormalizationMatchesBackendAlphabet() {
        assertEquals("ABC234567XYZ", TimetableSharingService.normalizeCode("a-b c 2 3 4 5 6 7 x_y-z"))
    }

    @Test
    fun backendNormalizationRemovesDigitsOutsideBase32Range() {
        assertEquals("ABCDILOEFGH", TimetableSharingService.normalizeCode("ABCD-01IL-OEFGH"))
    }
}
