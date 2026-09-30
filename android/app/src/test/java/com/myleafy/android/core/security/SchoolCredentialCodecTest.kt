package com.myleafy.android.core.security

import org.junit.Assert.*
import org.junit.Test

class SchoolCredentialCodecTest {
    @Test fun structuredCredentialsRoundTripSpecialCharacters() {
        val value=StoredSchoolCredential("bjfu","undergraduate","student","a||b\"\n中文",123)
        assertEquals(value,SchoolCredentialCodec.decode(SchoolCredentialCodec.encode(value)))
        assertFalse(value.toString().contains(value.password))
    }
    @Test fun recoverableLegacyEscapesMigrateAndAmbiguousRecordsRequireManualInput() {
        assertEquals("a|b||c",SchoolCredentialCodec.decode("bjfu|undergraduate|student|a||b||||c|123")?.password)
        assertEquals("pw",SchoolCredentialCodec.decode("bjfu|undergraduate|student|pw|123")?.password)
        assertNull(SchoolCredentialCodec.decode("bjfu|undergraduate|student|a|b|123"))
        assertNull(SchoolCredentialCodec.decode("general|undergraduate|student|pw|123"))
    }
}
