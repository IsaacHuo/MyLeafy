package com.myleafy.android.testing

import android.os.ParcelFileDescriptor
import androidx.test.platform.app.InstrumentationRegistry

/** Opt-in diagnostics collected while the test activity still owns its rendering window. */
internal fun resetRenderReview() {
    if (InstrumentationRegistry.getArguments().getString("performanceReview") != "true") return
    renderReviewShell("dumpsys gfxinfo ${InstrumentationRegistry.getInstrumentation().targetContext.packageName} reset")
}

internal fun captureRenderReview(name: String) {
    if (InstrumentationRegistry.getArguments().getString("performanceReview") != "true") return
    require(name.matches(Regex("[a-z-]+")))
    val pkg = InstrumentationRegistry.getInstrumentation().targetContext.packageName
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val output = renderReviewShell("dumpsys gfxinfo $pkg framestats")
    check(output.toString(Charsets.UTF_8).contains("Total frames rendered")) { "Renderer statistics unavailable" }
    java.io.File(checkNotNull(context.getExternalFilesDir(null)), "performance-$name.txt").writeBytes(output)
}

private fun renderReviewShell(command: String): ByteArray =
    ParcelFileDescriptor.AutoCloseInputStream(InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command)).use { it.readBytes() }
