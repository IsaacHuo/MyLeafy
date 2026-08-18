package com.myleafy.android.ui

import androidx.compose.runtime.Composable
import com.myleafy.android.navigation.MyLeafyNavHost

/**
 * 根组合入口。阶段 1 固定 5 个 Tab 的导航壳；
 * 后续按身份状态在 Login 与主壳之间切换（对应 iOS leafyApp 的决策逻辑）。
 */
@Composable
fun MyLeafyApp() {
    MyLeafyNavHost()
}
