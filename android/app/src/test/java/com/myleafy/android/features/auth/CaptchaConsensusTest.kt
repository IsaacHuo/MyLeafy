package com.myleafy.android.features.auth

import org.junit.Assert.*
import org.junit.Test

class CaptchaConsensusTest {
    @Test fun twoReliableVariantsMustAgreeOnExactlyFourAlphanumericCharacters() {
        assertEquals("ab12",CaptchaConsensus.candidate(listOf(CaptchaReading("AB 12",0.9f),CaptchaReading("ab12",0.85f))))
        assertNull(CaptchaConsensus.candidate(listOf(CaptchaReading("ab12",0.9f),CaptchaReading("a812",0.9f))))
        assertNull(CaptchaConsensus.candidate(listOf(CaptchaReading("ab12",0.9f),CaptchaReading("ab12",0.84f))))
        assertNull(CaptchaConsensus.candidate(listOf(CaptchaReading("ab12",Float.NaN),CaptchaReading("ab12",0.9f))))
        assertNull(CaptchaConsensus.candidate(listOf(CaptchaReading("ab123",0.9f),CaptchaReading("ab123",0.9f))))
    }
}
