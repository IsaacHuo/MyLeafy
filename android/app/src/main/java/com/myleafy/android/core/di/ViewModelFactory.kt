package com.myleafy.android.core.di

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.myleafy.android.MyLeafyApplication

/**
 * 从 Application 持有的 [AppContainer] 构造 ViewModel 的工厂。
 * 避免在无 Hilt 的情况下重复手写 Factory。
 */
inline fun <reified VM : ViewModel> appViewModelFactory(
    crossinline create: (AppContainer) -> VM,
): ViewModelProvider.Factory {
    return viewModelFactory {
        initializer {
            val application = this[ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY]
                as? MyLeafyApplication
                ?: error("MyLeafyApplication not found in CreationExtras")
            create(application.container)
        }
    }
}
