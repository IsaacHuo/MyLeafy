package com.myleafy.android.features.auth

import kotlinx.coroutines.Dispatchers
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
}

private class FakeAuthRepository(
    private val loginResult: Result<Unit>,
) : AuthRepository {
    var captchaFetchCount = 0
    override val hasCachedIdentity = false

    override suspend fun fetchUndergraduateCaptcha(): ByteArray {
        captchaFetchCount++
        return byteArrayOf(1, 2, 3)
    }

    override suspend fun loginUndergraduate(
        account: String,
        password: String,
        captcha: String,
    ): Result<Unit> = loginResult

    override suspend fun logout() = Unit
}
