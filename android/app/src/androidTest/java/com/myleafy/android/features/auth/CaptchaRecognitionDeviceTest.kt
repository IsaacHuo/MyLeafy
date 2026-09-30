package com.myleafy.android.features.auth

import android.graphics.*
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayOutputStream
import java.io.File

@RunWith(AndroidJUnit4::class)
class CaptchaRecognitionDeviceTest {
    @Test fun bundledModelRecognizesWithoutDownloadingAModel() = runBlocking {
        val bitmap = Bitmap.createBitmap(220,90,Bitmap.Config.ARGB_8888)
        val canvas=Canvas(bitmap);canvas.drawColor(Color.WHITE)
        canvas.drawText("AB12",15f,65f,Paint(Paint.ANTI_ALIAS_FLAG).apply { color=Color.BLACK;textSize=60f;typeface=Typeface.MONOSPACE })
        val bytes=ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) }.toByteArray()
        val readings=MlKitCaptchaRecognizer().readings(bytes)
        assertTrue("Bundled model must read text without a model download",readings.any { it.text.equals("ab12",true) })
    }

    @Test fun inspectSchoolSamplesOnlyWhenExplicitlyEnabled() = runBlocking {
        org.junit.Assume.assumeTrue(InstrumentationRegistry.getArguments().getString("schoolCaptchaSamples") == "true")
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val store=object:com.myleafy.android.core.security.SchoolSessionCookieStore {
            override fun load(scopeKey:String,portal:String)=emptyMap<String,String>()
            override fun save(cookies:Map<String,String>,scopeKey:String,portal:String)=Unit
            override fun delete(scopeKey:String,portal:String)=Unit
        }
        val client=com.myleafy.android.core.network.okhttp.OkHttpSchoolNetworkClient(store,
            com.myleafy.android.core.network.SchoolSessionState(),"http://newjwxt.bjfu.edu.cn",null,com.myleafy.android.parsers.JsoupHtmlParser())
        val directory=File(context.getExternalFilesDir(null),"captcha-review").apply { mkdirs() }
        var accepted=0
        for(index in 1..6){
            val challenge=client.prepareUndergraduateChallenge()
            val readings=MlKitCaptchaRecognizer().readings(challenge.imageBytes)
            val candidate=CaptchaConsensus.candidate(readings)
            File(directory,"captcha-$index.png").writeBytes(challenge.imageBytes)
            File(directory,"captcha-$index.txt").writeText(readings.joinToString("\n") { "${it.text}\t${it.confidence}" }+"\naccepted=${candidate.orEmpty()}")
            if(candidate!=null)accepted++
            kotlinx.coroutines.delay(300)
        }
        File(directory,"summary.txt").writeText("samples=6\naccepted=$accepted\nmanual=${6-accepted}")
    }
}
