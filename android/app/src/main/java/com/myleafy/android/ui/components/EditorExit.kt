package com.myleafy.android.ui.components

import androidx.activity.compose.BackHandler
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable

/** 返回按钮、系统返回和 Sheet 手势共用同一个放弃确认。保存成功直接退出。 */
@Composable
fun rememberEditorExit(hasChanges: Boolean, saving: Boolean, onExit: () -> Unit): () -> Unit {
    var confirm by rememberSaveable { mutableStateOf(false) }
    val requestExit: () -> Unit = {
        if (!saving) {
            if (hasChanges) confirm = true else onExit()
        }
    }
    BackHandler(onBack = requestExit)
    if (confirm) {
        LeafyAlertDialog(
            onDismissRequest = { confirm = false },
            title = { Text("放弃未保存的更改？") },
            confirmButton = {
                LeafyTextButton(onClick = { confirm = false; onExit() }) { Text("放弃更改") }
            },
            dismissButton = { LeafyTextButton(onClick = { confirm = false }) { Text("继续编辑") } },
        )
    }
    return requestExit
}
