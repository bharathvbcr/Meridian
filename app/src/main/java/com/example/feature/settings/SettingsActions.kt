package com.example.feature.settings

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import com.example.BuildConfig

internal const val LEGAL_LAST_UPDATED = "June 2026"

internal object SettingsUrls {
    const val GOOGLE_PRIVACY = "https://policies.google.com/privacy"
    const val FIREBASE_TERMS = "https://firebase.google.com/terms"
    const val GEMINI_APPS_PRIVACY = "https://support.google.com/gemini/answer/13594961"
}

internal fun appVersionName(context: Context): String =
    runCatching {
        context.packageManager.getPackageInfo(context.packageName, 0).versionName
    }.getOrNull() ?: BuildConfig.VERSION_NAME

internal fun appVersionLabel(context: Context): String =
    runCatching {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        val name = info.versionName ?: BuildConfig.VERSION_NAME
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        "$name ($code)"
    }.getOrDefault("${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")

internal fun buildDiagnosticText(context: Context): String {
    val version = appVersionLabel(context)
    val buildType = if (BuildConfig.DEBUG) "debug" else "release"
    return buildString {
        appendLine("Meridian diagnostics")
        appendLine("Version: $version")
        appendLine("Build: $buildType")
        appendLine("Package: ${context.packageName}")
        appendLine("Android: ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
        appendLine("Device: ${Build.MANUFACTURER} ${Build.MODEL}")
    }.trimEnd()
}

internal fun openAppSettings(context: Context) {
    context.startActivity(
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", context.packageName, null)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        },
    )
}

internal fun openWebUrl(context: Context, url: String) {
    context.startActivity(
        Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
    )
}

internal fun openPlayStoreListing(context: Context) {
    val packageName = context.packageName
    val marketIntent = Intent(
        Intent.ACTION_VIEW,
        Uri.parse("market://details?id=$packageName"),
    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    val webIntent = Intent(
        Intent.ACTION_VIEW,
        Uri.parse("https://play.google.com/store/apps/details?id=$packageName"),
    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { context.startActivity(marketIntent) }
        .onFailure { context.startActivity(webIntent) }
}

internal fun openFeedback(context: Context) {
    val versionName = appVersionName(context)
    val body = buildDiagnosticText(context) + "\n\nDescribe your feedback:\n"
    val mailto = Intent(Intent.ACTION_SENDTO).apply {
        data = Uri.parse("mailto:")
        putExtra(Intent.EXTRA_SUBJECT, "Meridian feedback (v$versionName)")
        putExtra(Intent.EXTRA_TEXT, body)
    }
    val share = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, "Meridian feedback (v$versionName)")
        putExtra(Intent.EXTRA_TEXT, body)
    }
    val chooser = if (mailto.resolveActivity(context.packageManager) != null) {
        Intent.createChooser(mailto, "Send feedback")
    } else {
        Intent.createChooser(share, "Send feedback")
    }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { context.startActivity(chooser) }
}
