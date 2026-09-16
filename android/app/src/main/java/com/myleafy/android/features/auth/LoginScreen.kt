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

    if (uiState.loginSucceeded) {
        LaunchedEffect(Unit) { onBack() }
    }

    LoginContent(
        state = uiState,
        account = account,
        password = password,
        captcha = captcha,
        onAccountChange = { account = it },
        onPasswordChange = { password = it },
        onCaptchaChange = { captcha = it },
        onSubmit = { viewModel.submit(account, password, captcha) },
        onRefreshCaptcha = viewModel::refreshCaptcha,
        onBack = onBack,
        modifier = modifier,
    )
}

/**
 * 由 state 驱动的登录表单：表单内容、提交与刷新验证码等副作用都由 [LoginScreen] 持有，
 * 这里只消费 state 与回调，便于截图与预览直接给定状态。
 * 本组件自身仍保留两项瞬时 UI 状态——密码显隐与输入焦点——它们不承载业务语义。
 */
@Composable
fun LoginContent(
    state: LoginUiState,
    account: String,
    password: String,
    captcha: String,
    onAccountChange: (String) -> Unit,
    onPasswordChange: (String) -> Unit,
    onCaptchaChange: (String) -> Unit,
    onSubmit: () -> Unit,
    onRefreshCaptcha: () -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var passwordVisible by rememberSaveable { mutableStateOf(false) }
    val passwordFocus = remember { FocusRequester() }
    val captchaFocus = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current

    LeafySecondaryScaffold(title = "学校登录", onBack = onBack, modifier = modifier) { contentModifier ->
        Box(modifier = contentModifier.fillMaxSize().imePadding()) {
            Column(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .widthIn(max = LeafyComponentSize.formMaxWidth)
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = LeafySpacing.page, vertical = LeafySpacing.card),
            ) {

        OutlinedTextField(
            value = account,
            onValueChange = onAccountChange,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("学号") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            keyboardActions = KeyboardActions(onNext = { passwordFocus.requestFocus() }),
        )
        Spacer(modifier = Modifier.height(LeafySpacing.compact))
        OutlinedTextField(
            value = password,
            onValueChange = onPasswordChange,
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
                onValueChange = onCaptchaChange,
                modifier = Modifier.weight(1f).focusRequester(captchaFocus),
                label = { Text("验证码") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = {
                    focusManager.clearFocus()
                    if (!state.isSubmitting) onSubmit()
                }),
            )
            Spacer(modifier = Modifier.width(LeafySpacing.compact))
            CaptchaImage(
                captchaBytes = state.captchaBytes,
                isLoading = state.isCaptchaLoading,
                onRefresh = onRefreshCaptcha,
            )
        }
        Spacer(modifier = Modifier.height(LeafySpacing.card))

        val errorMessage = state.errorMessage
        Box(modifier = Modifier.fillMaxWidth().heightIn(min = LeafyComponentSize.minimumTouchTarget)) {
            if (errorMessage != null) {
                LeafyStatusBanner(message = errorMessage, isError = true)
            }
        }

            LeafyPrimaryButton(
                onClick = onSubmit,
                modifier = Modifier.fillMaxWidth(),
                enabled = !state.isSubmitting,
            ) {
                if (state.isSubmitting) {
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
