package com.myleafy.android.core.network

/**
 * 当前学校会话状态（内存态）。
 * 身份与登录标志驱动 Cookie 作用域与页面显示；
 * 持久化（SettingsStore eduId / 凭据）由 AuthRepository 负责。
 */
class SchoolSessionState(
    private val activeAppScopeStore: com.myleafy.android.core.campus.ActiveAppScopeStore =
        com.myleafy.android.core.campus.ActiveAppScopeStore(),
) {
    var identity: CampusIdentity? = null
        internal set(value) {
            field = value
            if (value == null) activeAppScopeStore.clear() else activeAppScopeStore.activate(value)
        }

    var isLoggedIn: Boolean = false
        private set

    fun markLoggedIn(identity: CampusIdentity) {
        this.identity = identity
        isLoggedIn = true
    }

    fun clear() {
        identity = null
        isLoggedIn = false
    }
}
