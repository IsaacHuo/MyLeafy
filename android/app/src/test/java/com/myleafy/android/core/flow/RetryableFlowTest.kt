package com.myleafy.android.core.flow

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class RetryableFlowTest {

    /**
     * 首读失败后点「重新加载」必须真的重读：失败只结束当前这次订阅。
     * 如果 catch 写在 flatMapLatest 外面，token 变化不会再触发订阅，
     * 第二次断言会仍然停在错误状态。
     */
    @Test
    fun failedFirstReadIsRetriedByBumpingToken() = runTest {
        val retryToken = MutableStateFlow(0)
        var reads = 0
        val localSource = flow {
            reads += 1
            if (reads == 1) throw IllegalStateException("本地读取失败")
            emit("已恢复")
        }
        val states = mutableListOf<String>()
        val job = launch {
            retryableFlow(retryToken, localSource) { "错误：${it.message}" }
                .collect { states += it }
        }
        runCurrent()
        assertEquals(listOf("错误：本地读取失败"), states)

        retryToken.value = 1
        runCurrent()
        assertEquals(listOf("错误：本地读取失败", "已恢复"), states)
        assertEquals(2, reads)
        job.cancel()
    }
}
