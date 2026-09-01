package com.myleafy.android.features.auth

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafyButtonDefaults
import com.myleafy.android.ui.components.leafyMinimumTouchTarget
import com.myleafy.android.ui.theme.LeafyComponentSize
import com.myleafy.android.ui.theme.LeafyIconSize
import com.myleafy.android.ui.theme.LeafySpacing

/**
 * 学校登录页（M2.2：强智登录）。验证码自动获取、点击刷新；
 * 登录成功后自动返回。
 */
@Composable
fun LoginScreen(
    onBack: () -> Unit,
    viewModel: LoginViewModel = viewModel(
        factory = appViewModelFactory { container ->
            LoginViewModel(repository = container.authRepository)
        },
    ),
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()
    var account by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var captcha by rememberSaveable { mutableStateOf("") }
    var passwordVisible by rememberSaveable { mutableStateOf(false) }

    if (uiState.loginSucceeded) {
        LaunchedEffect(Unit) { onBack() }
    }

    LeafySecondaryScaffold(title = "学校登录", onBack = onBack, modifier = modifier) { contentModifier ->
        Box(modifier = contentModifier.fillMaxSize().imePadding()) {
            Column(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .fillMaxWidth()
                    .widthIn(max = LeafyComponentSize.formMaxWidth)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = LeafySpacing.page, vertical = LeafySpacing.card),
            ) {

        OutlinedTextField(
            value = account,
            onValueChange = { account = it },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("学号") },
            singleLine = true,
        )
        Spacer(modifier = Modifier.height(LeafySpacing.compact))
        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("密码") },
            singleLine = true,
            visualTransformation = if (passwordVisible) VisualTransformation.None else PasswordVisualTransformation(),
            trailingIcon = {
                IconButton(
                    onClick = { passwordVisible = !passwordVisible },
                    modifier = Modifier.size(LeafyComponentSize.minimumTouchTarget),
                ) {
                    Icon(
                        if (passwordVisible) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                        contentDescription = if (passwordVisible) "隐藏密码" else "显示密码",
                    )
                }
            },
        )
        Spacer(modifier = Modifier.height(LeafySpacing.compact))
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                value = captcha,
                onValueChange = { captcha = it },
                modifier = Modifier.weight(1f),
                label = { Text("验证码") },
                singleLine = true,
            )
            Spacer(modifier = Modifier.width(LeafySpacing.compact))
            CaptchaImage(
                captchaBytes = uiState.captchaBytes,
                isLoading = uiState.isCaptchaLoading,
                onRefresh = viewModel::refreshCaptcha,
            )
        }
        Spacer(modifier = Modifier.height(LeafySpacing.card))

        val errorMessage = uiState.errorMessage
        Box(modifier = Modifier.fillMaxWidth().heightIn(min = LeafyComponentSize.minimumTouchTarget)) {
            if (errorMessage != null) {
                Text(
                    text = errorMessage,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.align(Alignment.CenterStart),
                )
            }
        }

            Button(
                onClick = { viewModel.submit(account, password, captcha) },
                modifier = Modifier.fillMaxWidth().leafyMinimumTouchTarget(),
                enabled = !uiState.isSubmitting,
                shape = LeafyButtonDefaults.shape,
            ) {
                if (uiState.isSubmitting) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(LeafyIconSize.standard),
                        strokeWidth = 2.dp,
                    )
                } else {
                    Text("登录")
                }
            }
            Spacer(modifier = Modifier.height(LeafySpacing.section))
            }
        }
    }
}

@Composable
private fun CaptchaImage(
    captchaBytes: ByteArray?,
    isLoading: Boolean,
    onRefresh: () -> Unit,
) {
    Surface(
        onClick = onRefresh,
        modifier = Modifier.size(96.dp, LeafyComponentSize.minimumTouchTarget),
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
    ) {
        Box(contentAlignment = Alignment.Center) {
            when {
                isLoading -> CircularProgressIndicator(modifier = Modifier.size(LeafyIconSize.standard))
                captchaBytes == null -> Text(
                    text = "刷新",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                )
                else -> {
                    val bitmap = remember(captchaBytes) {
                        BitmapFactory.decodeByteArray(captchaBytes, 0, captchaBytes.size)
                    }
                    if (bitmap != null) {
                        Image(
                            bitmap = bitmap.asImageBitmap(),
                            contentDescription = "验证码（点击刷新）",
                            modifier = Modifier.fillMaxSize(),
                            contentScale = ContentScale.Fit,
                        )
                    } else {
                        Text(
                            text = "点击刷新",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
        }
    }
}
