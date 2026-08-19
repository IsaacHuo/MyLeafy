package com.myleafy.android.services.supabase

import com.myleafy.android.services.SupabaseConfig
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.postgrest.Postgrest

/**
 * Supabase 客户端提供者。仅使用公开的 project URL 与 publishable/anon key
 * （来自 git-ignored secrets.properties，写入 BuildConfig）。
 * 未配置时返回 null（调用方如实展示错误）。
 */
object SupabaseClientProvider {

    fun create(): SupabaseClient? {
        if (!SupabaseConfig.isConfigured) return null
        return createSupabaseClient(
            supabaseUrl = SupabaseConfig.supabaseUrl,
            supabaseKey = SupabaseConfig.anonKey,
        ) {
            install(Auth)
            install(Postgrest)
            install(Functions)
        }
    }
}
