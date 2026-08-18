package com.myleafy.android.services

import com.myleafy.android.BuildConfig

/**
 * Supabase 客户端配置（对应 iOS `SupabaseConfig`）。
 *
 * 仅允许公开的 project URL 与 publishable/anon key（来自 git-ignored
 * `android/secrets.properties`，写入 BuildConfig）。严禁 service_role key。
 */
object SupabaseConfig {
    val supabaseUrl: String = BuildConfig.SUPABASE_URL
    val anonKey: String = BuildConfig.SUPABASE_ANON_KEY

    val isConfigured: Boolean
        get() = supabaseUrl.startsWith("https://") &&
            anonKey.startsWith("sb_publishable_") &&
            !anonKey.contains("xxx") &&
            !supabaseUrl.contains("your-project-ref")
}
