package com.myleafy.android.ui.components

import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.VisualTransformation
import com.myleafy.android.ui.theme.leafySurfaces

/** Grouped form field: stable label and native editing/IME semantics. */
@Composable
fun LeafyTextField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    readOnly: Boolean = false,
    label: (@Composable () -> Unit)? = null,
    placeholder: (@Composable () -> Unit)? = null,
    leadingIcon: (@Composable () -> Unit)? = null,
    trailingIcon: (@Composable () -> Unit)? = null,
    supportingText: (@Composable () -> Unit)? = null,
    isError: Boolean = false,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
    singleLine: Boolean = false,
    minLines: Int = 1,
    maxLines: Int = if (singleLine) 1 else Int.MAX_VALUE,
) {
    OutlinedTextField(
        value = value, onValueChange = onValueChange, modifier = modifier,
        enabled = enabled, readOnly = readOnly, label = label, placeholder = placeholder,
        leadingIcon = leadingIcon, trailingIcon = trailingIcon, supportingText = supportingText,
        isError = isError, visualTransformation = visualTransformation,
        keyboardOptions = keyboardOptions, keyboardActions = keyboardActions,
        singleLine = singleLine, minLines = minLines, maxLines = maxLines,
        shape = MaterialTheme.shapes.medium,
        textStyle = MaterialTheme.typography.bodyLarge,
        colors = OutlinedTextFieldDefaults.colors(
            focusedContainerColor = MaterialTheme.leafySurfaces.content,
            unfocusedContainerColor = MaterialTheme.leafySurfaces.content,
            disabledContainerColor = MaterialTheme.leafySurfaces.grouped,
            unfocusedBorderColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.45f),
        ),
    )
}
