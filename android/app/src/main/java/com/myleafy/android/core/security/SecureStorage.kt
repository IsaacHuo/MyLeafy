package com.myleafy.android.core.security

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import java.security.InvalidAlgorithmParameterException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** 读取结果区分“没有条目”“读到了”和“条目存在但解不开”，避免把密钥失效当成首次使用。 */
sealed interface SecureReadResult {
    data object Missing : SecureReadResult
    data class Found(val value: String) : SecureReadResult
    data class Unreadable(val cause: Throwable) : SecureReadResult
}

/**
 * 基于 Android Keystore 的 AES-GCM 加密存储。
 *
 * 对应 iOS 的 Keychain 凭据/会话存储：
 * - 学校登录凭据（学号/密码）
 * - 教务会话 Cookie 字典
 *
 * 明文不落盘，密文以 Base64 存入私有 SharedPreferences。
 * 写入使用 commit：登出和保存凭据都必须在返回前真正落盘，否则进程被杀后
 * 可能出现“已登出但会话仍在”或“已登录但下次不自动填充”。
 */
class SecureStorage(context: Context) {

    private val alias = "myleafy_secure_key"
    private val prefs = context.applicationContext.getSharedPreferences(
        PREF_NAME, Context.MODE_PRIVATE,
    )
    private val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }

    fun save(key: String, plaintext: String) {
        val encrypted = encrypt(plaintext)
        check(prefs.edit().putString(key, encrypted).commit()) {
            "加密凭据写入失败"
        }
    }

    fun read(key: String): SecureReadResult {
        val encrypted = prefs.getString(key, null) ?: return SecureReadResult.Missing
        return try {
            SecureReadResult.Found(decrypt(encrypted))
        } catch (failure: Exception) {
            Log.e(TAG, "Unable to decrypt secure value for key=$key", failure)
            SecureReadResult.Unreadable(failure)
        }
    }

    fun remove(key: String) {
        check(prefs.edit().remove(key).commit()) { "加密凭据删除失败" }
    }

    fun removeKeysWithPrefix(prefix: String) {
        val keys = prefs.all.keys.filter { it.startsWith(prefix) }
        if (keys.isNotEmpty()) prefs.edit().apply { keys.forEach { remove(it) } }.apply()
    }

    private fun encrypt(plaintext: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val iv = cipher.iv
        val cipherText = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        val payload = iv + cipherText
        return Base64.encodeToString(payload, Base64.NO_WRAP)
    }

    private fun decrypt(encoded: String): String {
        val payload = Base64.decode(encoded, Base64.NO_WRAP)
        require(payload.size > IV_LENGTH) { "加密凭据长度异常" }
        val iv = payload.copyOfRange(0, IV_LENGTH)
        val cipherText = payload.copyOfRange(IV_LENGTH, payload.size)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(TAG_BITS, iv))
        return String(cipher.doFinal(cipherText), Charsets.UTF_8)
    }

    private fun getOrCreateKey(): SecretKey {
        (keyStore.getKey(alias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
        val parameters = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)

        // 对齐 iOS 的 WhenUnlockedThisDeviceOnly：设备未解锁时不可用。
        // 个别设备不支持该标志时退回普通 Keystore key，并保留告警。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            parameters.setUnlockedDeviceRequired(true)
        }
        val key = try {
            generator.init(parameters.build())
            generator.generateKey()
        } catch (unsupported: InvalidAlgorithmParameterException) {
            Log.w(TAG, "Unlocked-device-required key is not supported; falling back", unsupported)
            val fallback = KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
            generator.init(fallback)
            generator.generateKey()
        }
        return key
    }

    private companion object {
        const val TAG = "SecureStorage"
        const val PREF_NAME = "myleafy_secure_store"
        const val KEYSTORE_PROVIDER = "AndroidKeyStore"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_LENGTH = 12
        const val TAG_BITS = 128
    }
}
