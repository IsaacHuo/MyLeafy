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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Icon
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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafyActionIconButton
import com.myleafy.android.ui.components.LeafyPrimaryButton
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.theme.LeafyComponentSize
import com.myleafy.android.ui.theme.LeafyIconSize
import com.myleafy.android.ui.theme.LeafyLoginTokens
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.LeafyStroke

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
    val passwordFocus = remember { FocusRequester() }
    val captchaFocus = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current

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
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            keyboardActions = KeyboardActions(onNext = { passwordFocus.requestFocus() }),
        )
        Spacer(modifier = Modifier.height(LeafySpacing.compact))
        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            modifier = Modifier.fillMaxWidth().focusRequester(passwordFocus),
            label = { Text("密码") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Next),
            keyboardActions = KeyboardActions(onNext = { captchaFocus.requestFocus() }),
            visualTransformation = if (passwordVisible) VisualTransformation.None else PasswordVisualTransformation(),
            trailingIcon = {
                LeafyActionIconButton(
                    onClick = { passwordVisible = !passwordVisible },
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
                modifier = Modifier.weight(1f).focusRequester(captchaFocus),
                label = { Text("验证码") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = {
                    focusManager.clearFocus()
                    if (!uiState.isSubmitting) viewModel.submit(account, password, captcha)
                }),
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
                LeafyStatusBanner(message = errorMessage, isError = true)
            }
        }

            LeafyPrimaryButton(
                onClick = { viewModel.submit(account, password, captcha) },
                modifier = Modifier.fillMaxWidth(),
                enabled = !uiState.isSubmitting,
            ) {
                if (uiState.isSubmitting) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(LeafyIconSize.standard),
                        strokeWidth = LeafyStroke.progress,
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
        modifier = Modifier.size(LeafyLoginTokens.captchaWidth, LeafyComponentSize.minimumTouchTarget),
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
