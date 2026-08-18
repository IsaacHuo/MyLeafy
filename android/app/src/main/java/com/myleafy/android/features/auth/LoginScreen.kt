package com.myleafy.android.features.auth

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.myleafy.android.core.di.appViewModelFactory

/**
 * 学校登录页。阶段 1.5 为真实表单 + 状态机；阶段 2 接入验证码与
 * 强智/研究生登录协议。
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
    var account by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var captcha by remember { mutableStateOf("") }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) {
                Icon(imageVector = Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
            }
            Text(text = "学校登录", style = MaterialTheme.typography.headlineSmall)
        }
        Spacer(modifier = Modifier.height(24.dp))

        OutlinedTextField(
            value = account,
            onValueChange = { account = it },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("学号") },
            singleLine = true,
        )
        Spacer(modifier = Modifier.height(12.dp))
        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("密码") },
            singleLine = true,
        )
        Spacer(modifier = Modifier.height(12.dp))
        OutlinedTextField(
            value = captcha,
            onValueChange = { captcha = it },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("验证码") },
            singleLine = true,
        )
        Spacer(modifier = Modifier.height(20.dp))

        val errorMessage = uiState.errorMessage
        if (errorMessage != null) {
            Text(
                text = errorMessage,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.error,
            )
            Spacer(modifier = Modifier.height(8.dp))
        }

        Button(
            onClick = { viewModel.submit(account, password, captcha) },
            modifier = Modifier.fillMaxWidth(),
            enabled = !uiState.isSubmitting,
        ) {
            if (uiState.isSubmitting) {
                CircularProgressIndicator(
                    modifier = Modifier.height(20.dp),
                    strokeWidth = 2.dp,
                )
            } else {
                Text("登录")
            }
        }

        if (uiState.loginSucceeded) {
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "登录成功（阶段 2 将接入教务系统）",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.primary,
            )
        }
    }
}
