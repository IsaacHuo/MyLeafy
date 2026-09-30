package com.myleafy.android.features.auth

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class LoginViewModelTest {
    private val dispatcher = StandardTestDispatcher()

    @Before
    fun setUp() = Dispatchers.setMain(dispatcher)

    @After
    fun tearDown() = Dispatchers.resetMain()

    @Test
    fun loginFailureSurvivesAutomaticCaptchaRefresh() = runTest(dispatcher) {
        val repository = FakeAuthRepository(
            loginResult = Result.failure(IllegalStateException("验证码错误")),
        )
        val viewModel = LoginViewModel(repository)
        testScheduler.advanceUntilIdle()

        viewModel.submit("student", "password", "1234")
        testScheduler.advanceUntilIdle()

        assertEquals(2, repository.captchaFetchCount)
        assertEquals("验证码错误", viewModel.uiState.value.errorMessage)
        assertNotNull(viewModel.uiState.value.captchaBytes)
        assertFalse(viewModel.uiState.value.isSubmitting)
    }

    @Test
    fun lateRecognitionCannotOverwriteManualInputOrSubmitLogin() = runTest(dispatcher) {
        val reading = CompletableDeferred<String?>()
        val repository = FakeAuthRepository(Result.success(Unit))
        val viewModel = LoginViewModel(repository, CaptchaRecognizer { reading.await() })
        testScheduler.advanceUntilIdle()
        viewModel.setCaptcha("manual")
        reading.complete("ab12")
        testScheduler.advanceUntilIdle()
        assertEquals("manual", viewModel.captcha.value)
        assertFalse(viewModel.uiState.value.loginSucceeded)
        assertEquals(0, repository.loginCount)
    }

    @Test
    fun refreshedChallengeRejectsAnOlderRecognitionResult() = runTest(dispatcher) {
        val first = CompletableDeferred<String?>()
        var reads = 0
        val repository = FakeAuthRepository(Result.success(Unit))
        val viewModel = LoginViewModel(repository, CaptchaRecognizer { if (++reads == 1) first.await() else "cd34" })
        testScheduler.advanceUntilIdle()
        viewModel.refreshCaptcha()
        testScheduler.advanceUntilIdle()
        first.complete("ab12")
        testScheduler.advanceUntilIdle()
        assertEquals("cd34", viewModel.captcha.value)
        assertEquals(2, repository.captchaFetchCount)
        assertEquals(0, repository.loginCount)
    }
}

private class FakeAuthRepository(
    private val loginResult: Result<Unit>,
) : AuthRepository {
    var captchaFetchCount = 0
    var loginCount = 0
    override val hasCachedIdentity = false

    override suspend fun prepareUndergraduateChallenge(): com.myleafy.android.core.network.SchoolCaptchaChallenge {
        captchaFetchCount++
        return com.myleafy.android.core.network.SchoolCaptchaChallenge(byteArrayOf(1, 2, 3))
    }

    override suspend fun loginUndergraduate(
        challenge: com.myleafy.android.core.network.SchoolCaptchaChallenge,
        account: String,
        password: String,
        captcha: String,
    ): Result<Unit> { loginCount++; return loginResult }

    override suspend fun logout() = Unit
}
