package com.myleafy.android.features.profile

import org.junit.Assert.*
import org.junit.Test

class UpdateIntegrityTest {
    private val signer = "c".repeat(64)
    private val info = AppUpdateInfo("com.myleafy.android-5","com.myleafy.android","official",5,"1.2.1",29,"更新","https://downloads.myleafy.space/android/official/5/MyLeafy-Android-1.2.1.apk","MyLeafy-Android-1.2.1.apk",7,"b".repeat(64),signer,"https://github.com/IsaacHuo/MyLeafy/releases/tag/android-v1.2.1")
    private val archive = UpdatePackageIdentity(info.packageName,5,"1.2.1",29,setOf(signer))
    @Test fun onlyTheExpectedPackageVersionAndInstalledSignerCanInstall() {
        UpdateIntegrity.validatePackage(info,archive,setOf(signer),36)
        assertThrows(IllegalStateException::class.java) { UpdateIntegrity.validatePackage(info,archive.copy(packageName="other"),setOf(signer),36) }
        assertThrows(IllegalStateException::class.java) { UpdateIntegrity.validatePackage(info,archive.copy(versionCode=4),setOf(signer),36) }
        assertThrows(IllegalStateException::class.java) { UpdateIntegrity.validatePackage(info,archive.copy(signers=setOf("d".repeat(64))),setOf(signer),36) }
        assertThrows(IllegalStateException::class.java) { UpdateIntegrity.validatePackage(info,archive,emptySet(),36) }
        assertThrows(IllegalStateException::class.java) { UpdateIntegrity.validatePackage(info,archive,setOf(signer),28) }
        assertThrows(IllegalStateException::class.java) { UpdateIntegrity.validatePackage(info,archive.copy(minSdk=28),setOf(signer),36) }
    }
    @Test fun byteDigestUsesFullSha256() {
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",UpdateIntegrity.sha256("abc".toByteArray()))
    }
}
