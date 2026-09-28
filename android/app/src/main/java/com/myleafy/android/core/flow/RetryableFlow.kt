package com.myleafy.android.core.flow

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.flatMapLatest

/**
 * 把「可重试的本地数据流」组合成页面状态流。
 *
 * 关键点是 `catch` 必须位于 `flatMapLatest` 内部。写成
 * `retryToken.flatMapLatest { source }.catch { emit(error) }` 时，第一次读取失败会
 * 结束整个外层订阅，此后 retryToken 再怎么变化都不会重新订阅，
 * 「重新加载」按钮因此永远无效。放在内部后，失败只结束当前这一次订阅，
 * token 变化会重新订阅并重读本地数据。
 */
@OptIn(ExperimentalCoroutinesApi::class)
fun <T> retryableFlow(
    retryToken: Flow<Int>,
    source: Flow<T>,
    onError: (Throwable) -> T,
): Flow<T> = retryToken.flatMapLatest {
    source.catch { emit(onError(it)) }
}
