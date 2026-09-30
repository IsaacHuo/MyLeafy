package com.myleafy.android.features.auth

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import com.myleafy.android.core.security.StoredSchoolCredential
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
    fun savedCredentialsPrefillAndCaptchaStaysManual() = runTest(dispatcher) {
        val stored = StoredSchoolCredential("bjfu", "undergraduate", "student", "p|a\"ss", 1)
        val repository = FakeAuthRepository(Result.success(Unit), stored)
        val viewModel = LoginViewModel(repository)
        assertEquals(stored.password, viewModel.password.first { it.isNotEmpty() })
        assertEquals(stored.account, viewModel.account.value)
        assertEquals("", viewModel.captcha.value)
        assertEquals(0, repository.loginCount)
    }

    @Test
    fun failedLoginRetainsAccountAndPasswordAfterRefreshingCaptcha() = runTest(dispatcher) {
        val repository = FakeAuthRepository(Result.failure(IllegalStateException("验证码错误")))
        val viewModel = LoginViewModel(repository)
        testScheduler.advanceUntilIdle()
        viewModel.setAccount("student")
        viewModel.setPassword("p|a\"ss")
        viewModel.setCaptcha("1234")
        viewModel.submit()
        testScheduler.advanceUntilIdle()
        assertEquals("student", viewModel.account.value)
        assertEquals("p|a\"ss", viewModel.password.value)
        assertEquals("", viewModel.captcha.value)
        assertEquals("验证码错误", viewModel.uiState.value.errorMessage)
    }

}

private class FakeAuthRepository(
    private val loginResult: Result<Unit>,
    private val storedCredential: StoredSchoolCredential? = null,
) : AuthRepository {
    var captchaFetchCount = 0
    var loginCount = 0
    override fun cachedCredential() = storedCredential
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
