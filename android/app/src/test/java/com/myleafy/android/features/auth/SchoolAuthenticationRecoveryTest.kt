package com.myleafy.android.features.auth

import com.myleafy.android.core.campus.*
import com.myleafy.android.core.network.*
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test
import java.lang.reflect.Proxy

class SchoolAuthenticationRecoveryTest {
    private val identity = CampusIdentity(CampusID.bjfu,"student",null,SchoolPortal.UNDERGRADUATE,CampusIdentity.IdentityKind.SCHOOL_PORTAL)
    private fun client(handler: (String, Array<out Any?>) -> Any?): SchoolNetworkClient = Proxy.newProxyInstance(
        SchoolNetworkClient::class.java.classLoader, arrayOf(SchoolNetworkClient::class.java)) { _, method, args ->
            try { handler(method.name, args.orEmpty()) }
            catch (error: Exception) {
                @Suppress("UNCHECKED_CAST")
                val continuation = args!!.last() as kotlin.coroutines.Continuation<Any?>
                continuation.resumeWith(Result.failure(error))
                kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
            }
        } as SchoolNetworkClient

    @Test fun parallelExpiredQueriesShareOneManualChallengeWithoutSubmittingLogin() = runTest {
        val scopes = ActiveAppScopeStore().apply { activate(identity) }
        var challenges = 0
        val queries = mutableListOf<List<Any?>>()
        val raw = client { name,args -> when(name) {
            "prepareUndergraduateChallenge" -> { challenges++; SchoolCaptchaChallenge(byteArrayOf(1)) }
            "fetchEmptyClassrooms" -> { queries += args.dropLast(1); throw SchoolNetworkError.SessionExpired }
            else -> error("Unexpected automatic login: $name")
        } }
        val recovery = SchoolAuthenticationRecovery(raw,scopes,backgroundScope)
        val wrapped = RecoveringSchoolNetworkClient(raw,recovery,scopes)
        val first = async { runCatching { wrapped.fetchEmptyClassrooms("2026-2027-1",4,2,3,8) } }
        val second = async { runCatching { wrapped.fetchEmptyClassrooms("2026-2027-1",5,1,1,13) } }
        assertTrue(first.await().exceptionOrNull() is SchoolNetworkError.AuthenticationRequired)
        assertTrue(second.await().exceptionOrNull() is SchoolNetworkError.AuthenticationRequired)
        assertEquals(1,challenges)
        assertEquals(1,queries.count { it == listOf("2026-2027-1",4,2,3,8) })
        assertEquals(1,queries.count { it == listOf("2026-2027-1",5,1,1,13) })
        recovery.manualChallenge()
        assertEquals(1,challenges)
    }

    @Test fun manualAuthenticationReleasesPendingRevisionAndRestoresOriginalQuery() = runTest {
        val scopes = ActiveAppScopeStore().apply { activate(identity) }
        var authenticated = false
        val queries = mutableListOf<List<Any?>>()
        val raw = client { name,args -> when(name) {
            "prepareUndergraduateChallenge" -> SchoolCaptchaChallenge(byteArrayOf(1))
            "fetchEmptyClassrooms" -> {
                queries += args.dropLast(1)
                if(!authenticated) throw SchoolNetworkError.SessionExpired
                emptyList<Any>()
            }
            else -> error(name)
        } }
        val recovery = SchoolAuthenticationRecovery(raw,scopes,backgroundScope)
        val wrapped = RecoveringSchoolNetworkClient(raw,recovery,scopes)
        assertTrue(runCatching { wrapped.fetchEmptyClassrooms("2026-2027-1",4,2,3,8) }.isFailure)
        authenticated = true
        recovery.manualAuthenticationCompleted()
        assertEquals(SchoolRecoveryResult.Authenticated,recovery.recover(0))
        wrapped.fetchEmptyClassrooms("2026-2027-1",4,2,3,8)
        assertEquals(listOf(queries.first(),queries.first()),queries)
    }

    @Test fun aNetworkFailureDoesNotAcquireANewLoginChallenge() = runTest {
        val scopes=ActiveAppScopeStore().apply { activate(identity) }
        val raw=client { name,_ -> if(name=="fetchGrades") throw java.io.IOException("offline") else error("Unexpected authentication") }
        val recovery=SchoolAuthenticationRecovery(raw,scopes,backgroundScope)
        val failure=runCatching { RecoveringSchoolNetworkClient(raw,recovery,scopes).fetchGrades() }.exceptionOrNull()
        assertTrue(failure is java.io.IOException)
    }

    @Test fun identityChangeDiscardsThePreviousManualChallenge() = runTest {
        val scopes=ActiveAppScopeStore().apply { activate(identity) }
        var challenges=0
        val raw=client { name,_ -> when(name) {
            "prepareUndergraduateChallenge" -> { challenges++; SchoolCaptchaChallenge(byteArrayOf(challenges.toByte())) }
            else -> error(name)
        } }
        val recovery=SchoolAuthenticationRecovery(raw,scopes,backgroundScope)
        recovery.recover(0)
        scopes.activate(identity.copy(eduId="another"))
        testScheduler.runCurrent()
        assertEquals(2,recovery.manualChallenge().imageBytes[0].toInt())
    }
}
