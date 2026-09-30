package com.myleafy.android.ui.components

import androidx.compose.runtime.*

class UpdatePresentationGate {
    var blockers by mutableIntStateOf(0)
        private set
    fun enter() { blockers++ }
    fun leave() { blockers-- }
}
val LocalUpdatePresentationGate = staticCompositionLocalOf<UpdatePresentationGate?> { null }
val LocalSchoolRecoveryProgress = staticCompositionLocalOf<String?> { null }

@Composable
fun DeferUpdatePrompt() {
    val gate = LocalUpdatePresentationGate.current
    DisposableEffect(gate) { gate?.enter(); onDispose { gate?.leave() } }
}
