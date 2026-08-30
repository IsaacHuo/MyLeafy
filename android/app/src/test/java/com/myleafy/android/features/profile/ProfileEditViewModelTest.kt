package com.myleafy.android.features.profile

import com.myleafy.android.shared.model.ProfileDto
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ProfileEditViewModelTest {
    private val dispatcher = StandardTestDispatcher()

    @Before
    fun setUp() = Dispatchers.setMain(dispatcher)

    @After
    fun tearDown() = Dispatchers.resetMain()

    @Test
    fun loadsAndSavesEditableCommunityFields() = runTest(dispatcher) {
        val repository = FakeProfileRepository()
        val viewModel = ProfileEditViewModel(repository)
        advanceUntilIdle()

        assertEquals("原昵称", viewModel.uiState.value.nickname)
        viewModel.updateNickname("新昵称")
        viewModel.updateBio("新的简介")
        viewModel.updateMajor("计算机")
        viewModel.updateGrade("2024")
        viewModel.save()
        advanceUntilIdle()

        assertEquals(listOf("新昵称", "新的简介", "计算机", "2024"), repository.lastUpdate)
        assertTrue(viewModel.uiState.value.saved)
        assertFalse(viewModel.uiState.value.isSaving)
    }

    @Test
    fun blankNicknameIsRejectedWithoutCallingRepository() = runTest(dispatcher) {
        val repository = FakeProfileRepository()
        val viewModel = ProfileEditViewModel(repository)
        advanceUntilIdle()

        viewModel.updateNickname("   ")
        viewModel.save()
        advanceUntilIdle()

        assertEquals(null, repository.lastUpdate)
        assertEquals("昵称不能为空", viewModel.uiState.value.error)
    }
}

private class FakeProfileRepository : ProfileRepository {
    override val isPlaceholder = false
    var lastUpdate: List<String>? = null

    override suspend fun fetchProfile(): ProfileDto = ProfileDto(
        id = "profile",
        nickname = "原昵称",
        bio = "原简介",
        major = "林学",
        grade = "2023",
        is_profile_complete = true,
    )

    override suspend fun updateProfile(
        nickname: String,
        bio: String?,
        major: String?,
        grade: String?,
    ): ProfileDto {
        lastUpdate = listOf(nickname, bio.orEmpty(), major.orEmpty(), grade.orEmpty())
        return fetchProfile().copy(
            nickname = nickname,
            bio = bio,
            major = major,
            grade = grade,
        )
    }
}
