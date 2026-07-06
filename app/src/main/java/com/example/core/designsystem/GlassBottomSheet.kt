package com.example.core.designsystem

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.chrisbanes.haze.HazeState

/**
 * Radius token for the sheet's top corners. Mirrors [GlassDefaults.cardShape] (28.dp = the
 * documented "large" radius) so the sheet chrome matches every glass card in the app.
 */
private val GlassSheetShape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)

/**
 * Local mirror of Meridian's documented 4/8/12/16/20/24 spacing scale, kept private to this
 * design-system file so the two platforms stay conceptually in parity without leaking new
 * public surface. Prefer these over ad-hoc dp literals inside this file's components.
 */
private object GlassSheetSpacing {
    val sm: Dp = 8.dp
    val lg: Dp = 16.dp
    val xxl: Dp = 24.dp
}

/**
 * Bottom sheet that slides up from the screen edge with frosted-glass chrome matching the rest
 * of the app. [blur] is disabled because the sheet renders in its own window layer (same
 * constraint as dropdown menus).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GlassBottomSheet(
    onDismissRequest: () -> Unit,
    hazeState: HazeState,
    modifier: Modifier = Modifier,
    sheetState: SheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    content: @Composable ColumnScope.() -> Unit,
) {
    ModalBottomSheet(
        onDismissRequest = onDismissRequest,
        sheetState = sheetState,
        shape = GlassSheetShape,
        containerColor = Color.Transparent,
        scrimColor = Color.Black.copy(alpha = 0.45f),
        dragHandle = null,
        modifier = modifier,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .liquidGlass(
                    hazeState = hazeState,
                    shape = GlassSheetShape,
                    tintColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.82f),
                    borderColor = Color.White.copy(alpha = 0.25f),
                    blur = false,
                ),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .imePadding(),
            ) {
                BottomSheetDefaults.DragHandle(modifier = Modifier.align(Alignment.CenterHorizontally))
                content()
            }
        }
    }
}

/** Form-style bottom sheet with a title, scrollable body, and trailing action buttons. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GlassFormBottomSheet(
    onDismissRequest: () -> Unit,
    hazeState: HazeState,
    title: @Composable () -> Unit,
    confirmButton: @Composable () -> Unit,
    dismissButton: @Composable () -> Unit = {},
    content: @Composable () -> Unit,
) {
    GlassBottomSheet(onDismissRequest = onDismissRequest, hazeState = hazeState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = GlassSheetSpacing.xxl)
                .padding(bottom = GlassSheetSpacing.lg),
        ) {
            title()
            Spacer(Modifier.height(GlassSheetSpacing.sm))
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState()),
            ) {
                content()
            }
            Spacer(Modifier.height(GlassSheetSpacing.lg))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(GlassSheetSpacing.sm, Alignment.End),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                dismissButton()
                confirmButton()
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GlassDatePickerSheet(
    onDismissRequest: () -> Unit,
    hazeState: HazeState,
    initialSelectedDateMillis: Long?,
    onConfirm: (Long) -> Unit,
) {
    val pickerState = rememberDatePickerState(initialSelectedDateMillis = initialSelectedDateMillis)
    GlassBottomSheet(onDismissRequest = onDismissRequest, hazeState = hazeState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = GlassSheetSpacing.lg),
        ) {
            Text(
                text = "Pick a date",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface,
                // Expose the sheet title as a heading so TalkBack users can jump to it,
                // matching how SectionHeader / GlassToolbar advertise their titles.
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = GlassSheetSpacing.xxl)
                    .padding(bottom = GlassSheetSpacing.sm)
                    .semantics { heading() },
            )
            DatePicker(
                state = pickerState,
                modifier = Modifier.fillMaxWidth(),
            )
            SheetActions(
                onDismissRequest = onDismissRequest,
                onConfirm = { pickerState.selectedDateMillis?.let(onConfirm) },
                confirmEnabled = pickerState.selectedDateMillis != null,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GlassTimePickerSheet(
    onDismissRequest: () -> Unit,
    hazeState: HazeState,
    initialHour: Int,
    initialMinute: Int,
    is24Hour: Boolean,
    onConfirm: (hour: Int, minute: Int) -> Unit,
) {
    val state = rememberTimePickerState(
        initialHour = initialHour,
        initialMinute = initialMinute,
        is24Hour = is24Hour,
    )
    GlassBottomSheet(onDismissRequest = onDismissRequest, hazeState = hazeState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = GlassSheetSpacing.lg),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = "Pick a time",
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurface,
                // Expose the sheet title as a heading so TalkBack users can jump to it,
                // matching how SectionHeader / GlassToolbar advertise their titles.
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = GlassSheetSpacing.xxl)
                    .padding(bottom = GlassSheetSpacing.sm)
                    .semantics { heading() },
            )
            TimePicker(
                state = state,
                modifier = Modifier.fillMaxWidth(),
            )
            SheetActions(
                onDismissRequest = onDismissRequest,
                onConfirm = { onConfirm(state.hour, state.minute) },
            )
        }
    }
}

/**
 * Shared Cancel / confirm action row for the date & time picker sheets.
 *
 * The confirm ("OK") is the primary affirmative action, so it gets a filled [Button] tinted with
 * [ColorScheme.primary] — mirroring EmptyStateCard's call-to-action — giving it clear visual
 * priority over the neutral Cancel [TextButton]. Both buttons carry
 * [minimumInteractiveComponentSize] so they honour the 48dp minimum touch target even though a
 * bare TextButton is only 40dp tall.
 */
@Composable
private fun SheetActions(
    onDismissRequest: () -> Unit,
    onConfirm: () -> Unit,
    modifier: Modifier = Modifier,
    confirmEnabled: Boolean = true,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = GlassSheetSpacing.xxl),
        horizontalArrangement = Arrangement.spacedBy(GlassSheetSpacing.sm, Alignment.End),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TextButton(
            onClick = onDismissRequest,
            modifier = Modifier.minimumInteractiveComponentSize(),
        ) {
            Text("Cancel", style = MaterialTheme.typography.labelLarge)
        }
        Button(
            onClick = onConfirm,
            enabled = confirmEnabled,
            modifier = Modifier.minimumInteractiveComponentSize(),
            shape = MaterialTheme.shapes.large,
            colors = ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.primary,
                contentColor = MaterialTheme.colorScheme.onPrimary,
            ),
        ) {
            Text("OK", style = MaterialTheme.typography.labelLarge)
        }
    }
}
