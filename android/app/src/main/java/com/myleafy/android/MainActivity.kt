package com.myleafy.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.myleafy.android.ui.MyLeafyApp
import com.myleafy.android.ui.theme.MyLeafyTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MyLeafyTheme {
                MyLeafyApp(deepLinkIntent = intent)
            }
        }
    }
}
