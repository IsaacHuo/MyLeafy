package com.myleafy.android.features.auth

import android.graphics.BitmapFactory
import android.net.ConnectivityManager
import android.net.Network
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.autofill.contentType
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory
import com.myleafy.android.ui.components.LeafyActionIconButton
import com.myleafy.android.ui.components.LeafyPrimaryButton
import com.myleafy.android.ui.components.LeafySecondaryScaffold
import com.myleafy.android.ui.components.LeafyStatusBanner
import com.myleafy.android.ui.theme.LeafyAlpha
import com.myleafy.android.ui.theme.LeafyComponentSize
import com.myleafy.android.ui.theme.LeafyIconSize
import com.myleafy.android.ui.theme.LeafyLoginTokens
import com.myleafy.android.ui.theme.LeafySpacing
import com.myleafy.android.ui.theme.LeafyStroke
import com.myleafy.android.ui.theme.leafySurfaces
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 学校登录页（M2.2：强智登录）。验证码自动获取、点击刷新；
 * 登录成功后自动返回。
 */
@Composable
fun LoginScreen(
    onBack: () -> Unit,
    onLoggedIn: () -> Unit = onBack,
    viewModel: LoginViewModel = viewModel(
        factory = appViewModelFactory { container ->
            LoginViewModel(repository = container.authRepository)
        },
    ),
    modifier: Modifier = Modifier,
    entryHeader: (@Composable () -> Unit)? = null,
    onBusyChanged: (Boolean) -> Unit = {},
) {
    val uiState by viewModel.uiState.collectAsState()
    DisposableEffect(viewModel) {
        viewModel.resumeCaptcha()
        onDispose { viewModel.pauseCaptcha() }
    }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { viewModel.resumeCaptcha() }
    RememberNetworkAvailability { viewModel.resumeCaptcha() }
    LaunchedEffect(uiState.isSubmitting) { onBusyChanged(uiState.isSubmitting) }
    val account by viewModel.account.collectAsState()
    val password by viewModel.password.collectAsState()
    val captcha by viewModel.captcha.collectAsState()

    if (uiState.loginSucceeded) {
        LaunchedEffect(Unit) { onLoggedIn() }
    }

    LoginContent(
        state = uiState,
        account = account,
        password = password,
        captcha = captcha,
        onAccountChange = viewModel::setAccount,
        onPasswordChange = viewModel::setPassword,
        onCaptchaChange = viewModel::setCaptcha,
        onSubmit = { viewModel.submit(account, password, captcha) },
        onRefreshCaptcha = viewModel::refreshCaptcha,
        onBack = onBack,
        modifier = modifier,
        entryHeader = entryHeader,
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
    entryHeader: (@Composable () -> Unit)? = null,
) {
    var passwordVisible by rememberSaveable { mutableStateOf(false) }
    val passwordFocus = remember { FocusRequester() }
    val captchaFocus = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current

    val form: @Composable (Modifier) -> Unit = { formModifier ->
        Box(formModifier.fillMaxSize().imePadding()) {
            Column(
                Modifier
                    .align(if (entryHeader == null) Alignment.TopCenter else Alignment.Center)
                    .widthIn(max = LeafyComponentSize.formMaxWidth)
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = LeafySpacing.page, vertical = LeafySpacing.card),
            ) {
                entryHeader?.invoke()

                // iOS 把学号、密码、验证码放进同一张卡片，用 1px 分隔线组织行；
                // 这里保留 Material 的浮动标签语义，但去掉每个输入框自己的描边和间距。
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    shape = MaterialTheme.shapes.large,
                    color = MaterialTheme.leafySurfaces.content,
                    border = BorderStroke(
                        LeafyStroke.hairline,
                        MaterialTheme.colorScheme.outlineVariant.copy(alpha = LeafyAlpha.cardBorder),
                    ),
                    shadowElevation = com.myleafy.android.ui.theme.LeafyElevation.card,
                ) {
                    Column {
                        LoginTextField(
                            value = account,
                            onValueChange = onAccountChange,
                            label = "学号",
                            enabled = !state.isSubmitting,
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                            keyboardActions = KeyboardActions(onNext = { passwordFocus.requestFocus() }),
                            contentType = ContentType.Username,
                        )
                        LoginDivider()
                        LoginTextField(
                            value = password,
                            onValueChange = onPasswordChange,
                            label = "密码",
                            enabled = !state.isSubmitting,
                            keyboardOptions = KeyboardOptions(
                                keyboardType = KeyboardType.Password,
                                imeAction = ImeAction.Next,
                            ),
                            keyboardActions = KeyboardActions(onNext = { captchaFocus.requestFocus() }),
                            visualTransformation = if (passwordVisible) {
                                VisualTransformation.None
                            } else {
                                PasswordVisualTransformation()
                            },
                            trailingIcon = {
                                LeafyActionIconButton(onClick = { passwordVisible = !passwordVisible }) {
                                    Icon(
                                        if (passwordVisible) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                                        contentDescription = if (passwordVisible) "隐藏密码" else "显示密码",
                                    )
                                }
                            },
                            modifier = Modifier.focusRequester(passwordFocus),
                            contentType = ContentType.Password,
                        )
                        LoginDivider()
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            LoginTextField(
                                value = captcha,
                                onValueChange = onCaptchaChange,
                                label = "验证码",
                                enabled = !state.isSubmitting,
                                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                                keyboardActions = KeyboardActions(onDone = {
                                    focusManager.clearFocus()
                                    if (!state.isSubmitting) onSubmit()
                                }),
                                modifier = Modifier.weight(1f).focusRequester(captchaFocus),
                            )
                            CaptchaImage(
                                captchaBytes = state.captchaBytes,
                                isLoading = state.isCaptchaLoading,
                                onRefresh = onRefreshCaptcha,
                                modifier = Modifier.padding(end = LeafySpacing.compact),
                            )
                        }
                    }
                }

                state.errorMessage?.let { message ->
                    Spacer(modifier = Modifier.height(LeafySpacing.compact))
                    LeafyStatusBanner(message = message, isError = true)
                }

                Spacer(modifier = Modifier.height(LeafySpacing.card))
                LeafyPrimaryButton(
                    onClick = onSubmit,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !state.isSubmitting && !state.isCaptchaLoading &&
                        account.isNotBlank() && password.isNotBlank() && captcha.isNotBlank(),
                ) {
                    if (state.isSubmitting) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(LeafyIconSize.standard),
                            strokeWidth = LeafyStroke.progress,
                        )
                        Text("登录中…", modifier = Modifier.padding(start = LeafySpacing.micro))
                    } else {
                        Text("登录")
                    }
                }
                Spacer(modifier = Modifier.height(LeafySpacing.section))
            }
        }
    }
    if (entryHeader == null) {
        LeafySecondaryScaffold(title = "北林登录", onBack = onBack, modifier = modifier) { form(it) }
    } else {
        form(modifier)
    }
}

@Composable
private fun LoginTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    enabled: Boolean,
    keyboardOptions: KeyboardOptions,
    keyboardActions: KeyboardActions,
    modifier: Modifier = Modifier,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    trailingIcon: (@Composable () -> Unit)? = null,
    contentType: ContentType? = null,
) {
    TextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.fillMaxWidth().then(
            if (contentType != null) Modifier.contentType(contentType) else Modifier,
        ),
        enabled = enabled,
        label = { Text(label) },
        singleLine = true,
        shape = RectangleShape,
        visualTransformation = visualTransformation,
        trailingIcon = trailingIcon,
        keyboardOptions = keyboardOptions,
        keyboardActions = keyboardActions,
        colors = TextFieldDefaults.colors(
            focusedContainerColor = Color.Transparent,
            unfocusedContainerColor = Color.Transparent,
            disabledContainerColor = Color.Transparent,
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            disabledIndicatorColor = Color.Transparent,
            errorContainerColor = Color.Transparent,
            errorIndicatorColor = Color.Transparent,
        ),
    )
}

@Composable
private fun LoginDivider() {
    HorizontalDivider(
        modifier = Modifier.padding(horizontal = LeafySpacing.card),
        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = LeafyAlpha.divider),
    )
}

@Composable
private fun CaptchaImage(
    captchaBytes: ByteArray?,
    isLoading: Boolean,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val bitmap by produceState<ImageBitmap?>(initialValue = null, captchaBytes) {
        value = captchaBytes?.let { bytes ->
            withContext(Dispatchers.Default) {
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
            }
        }
    }
    Surface(
        onClick = onRefresh,
        modifier = modifier.size(LeafyLoginTokens.captchaWidth, LeafyComponentSize.minimumTouchTarget),
        shape = MaterialTheme.shapes.small,
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
    ) {
        Box(contentAlignment = Alignment.Center) {
            when {
                isLoading -> CircularProgressIndicator(modifier = Modifier.size(LeafyIconSize.standard))
                bitmap == null -> Text(
                    text = "刷新",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                )
                else -> Image(
                    bitmap = requireNotNull(bitmap),
                    contentDescription = "验证码（点击刷新）",
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Fit,
                    filterQuality = FilterQuality.None,
                )
            }
        }
    }
}

/** 网络恢复时补拉验证码，避免启动时断网后用户只能手动点刷新。 */
@Composable
private fun RememberNetworkAvailability(onAvailable: () -> Unit) {
    val context = LocalContext.current
    val current by rememberUpdatedState(onAvailable)
    DisposableEffect(context) {
        val manager = context.getSystemService(ConnectivityManager::class.java)
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                current()
            }
        }
        manager?.registerDefaultNetworkCallback(callback)
        onDispose { manager?.unregisterNetworkCallback(callback) }
    }
}
