package com.myleafy.android

import android.app.Application
import com.myleafy.android.core.di.AppContainer

class MyLeafyApplication : Application() {

    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        container.scheduleNotificationScheduler.enqueuePeriodicReconcile()
    }
}
