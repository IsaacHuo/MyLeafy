package com.myleafy.android.features.auth

import com.myleafy.android.core.campus.*
import com.myleafy.android.core.network.*
import com.myleafy.android.core.security.*
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test
import java.lang.reflect.Proxy

class SchoolAuthenticationRecoveryTest {
    private val identity = CampusIdentity(CampusID.bjfu,"student",null,SchoolPortal.UNDERGRADUATE,CampusIdentity.IdentityKind.SCHOOL_PORTAL)
    private val credentials = object : SchoolLoginCredentialStore {
        override fun save(credential: StoredSchoolCredential) = Unit
        override fun loadMostRecent(campusId: String) = StoredSchoolCredential("bjfu","undergraduate","student","a|b",1)
        override fun delete(campusId: String) = Unit
    }
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

    @Test fun parallelExpiredQueriesShareOneAuthenticationAndKeepExactQuery() = runTest {
        val scopes = ActiveAppScopeStore().apply { activate(identity) }
        var authenticated = false; var challenges = 0; var logins = 0
        val queries = mutableListOf<List<Any?>>()
        val raw = client { name,args -> when(name) {
            "prepareUndergraduateChallenge" -> { challenges++; SchoolCaptchaChallenge(byteArrayOf(1)) }
            "loginUndergraduate" -> { logins++; assertEquals("a|b",args[2]); authenticated = true; Unit }
            "fetchEmptyClassrooms" -> { queries += args.dropLast(1); if(!authenticated) throw SchoolNetworkError.SessionExpired; emptyList<Any>() }
            else -> error(name)
        } }
        val recovery = SchoolAuthenticationRecovery(raw,credentials,scopes,backgroundScope,CaptchaRecognizer { delay(20); "abcd" })
        val wrapped = RecoveringSchoolNetworkClient(raw,recovery,scopes)
        val first = async { wrapped.fetchEmptyClassrooms("2026-2027-1",4,2,3,8) }
        val second = async { wrapped.fetchEmptyClassrooms("2026-2027-1",5,1,1,13) }
        first.await();second.await()
        assertEquals(1,challenges);assertEquals(1,logins)
        assertEquals(2,queries.count { it == listOf("2026-2027-1",4,2,3,8) })
        assertEquals(2,queries.count { it == listOf("2026-2027-1",5,1,1,13) })
    }

    @Test fun lowConfidenceUsesThreeChallengesAndPreservesLastForManualInput() = runTest {
        val scopes = ActiveAppScopeStore().apply { activate(identity) }
        var count = 0
        val raw = client { name,_ -> when(name) {
            "prepareUndergraduateChallenge" -> { count++; SchoolCaptchaChallenge(byteArrayOf(count.toByte())) }
            else -> error("Unexpected submission: $name")
        } }
        val recovery=SchoolAuthenticationRecovery(raw,credentials,scopes,backgroundScope,CaptchaRecognizer { null })
        assertTrue(recovery.recover(0) is SchoolRecoveryResult.Manual)
        assertEquals(3,count)
        // A concurrent request that already observed the same expired revision cannot start another round.
        assertTrue(recovery.recover(0) is SchoolRecoveryResult.Manual)
        assertEquals(3,recovery.manualChallenge().imageBytes[0].toInt());assertEquals(3,count)
    }

    @Test fun wrongPasswordStopsAfterOneSubmission() = runTest {
        val scopes=ActiveAppScopeStore().apply { activate(identity) }; var logins=0
        val raw=client { name,_ -> when(name) {
            "prepareUndergraduateChallenge" -> SchoolCaptchaChallenge(byteArrayOf(1))
            "loginUndergraduate" -> { logins++;throw SchoolNetworkError.LoginFailed("密码错误") }
            else -> error(name)
        } }
        val recovery=SchoolAuthenticationRecovery(raw,credentials,scopes,backgroundScope,CaptchaRecognizer { "abcd" })
        val result=recovery.recover(0) as SchoolRecoveryResult.Manual
        assertEquals("密码错误",result.message);assertEquals(1,logins)
    }

    @Test fun aNetworkFailureDoesNotAuthenticate() = runTest {
        val scopes=ActiveAppScopeStore().apply { activate(identity) }
        val raw=client { name,_ -> if(name=="fetchGrades") throw java.io.IOException("offline") else error("Unexpected authentication") }
        val recovery=SchoolAuthenticationRecovery(raw,credentials,scopes,backgroundScope,CaptchaRecognizer { error("Unexpected OCR") })
        val failure=runCatching { RecoveringSchoolNetworkClient(raw,recovery,scopes).fetchGrades() }.exceptionOrNull()
        assertTrue(failure is java.io.IOException)
    }

    @Test fun ambiguousLoginErrorsCannotStartAnotherCaptchaSubmission() = runTest {
        for (message in listOf("登录失败，请检查学号与验证码", "密码或验证码错误")) {
            val scopes = ActiveAppScopeStore().apply { activate(identity) }
            var logins = 0
            val raw = client { name,_ -> when(name) {
                "prepareUndergraduateChallenge" -> SchoolCaptchaChallenge(byteArrayOf(1))
                "loginUndergraduate" -> { logins++; throw SchoolNetworkError.LoginFailed(message) }
                else -> error(name)
            } }
            val recovery = SchoolAuthenticationRecovery(raw,credentials,scopes,backgroundScope,CaptchaRecognizer { "abcd" })
            assertTrue(recovery.recover(0) is SchoolRecoveryResult.Manual)
            assertEquals(1,logins)
        }
    }

    @Test fun credentialsFromAnotherAccountAreNeverSubmitted() = runTest {
        val scopes=ActiveAppScopeStore().apply { activate(identity.copy(eduId="another")) }
        val raw=client { _,_->error("Must not contact school") }
        val recovery=SchoolAuthenticationRecovery(raw,credentials,scopes,backgroundScope,CaptchaRecognizer { error("Unexpected OCR") })
        assertTrue(recovery.recover(0) is SchoolRecoveryResult.Manual)
    }
}
