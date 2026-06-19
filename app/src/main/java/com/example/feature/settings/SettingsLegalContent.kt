package com.example.feature.settings

internal enum class LegalDocument(
    val title: String,
    val body: String,
    val externalUrl: String? = null,
    val externalLabel: String? = null,
) {
    PRIVACY(
        title = "Privacy notice",
        body = """
            Meridian is built around on-device processing. Your clocks, saved zones, planner data, and settings are stored locally on your phone.

            What Meridian may access
            • Location — only when you choose “Use my location” to resolve your home time zone. Coordinates are not uploaded to Meridian servers.
            • Calendar — read-only access to show events on the planner when you grant permission.
            • Contacts — read-only access to import people into the planner when you grant permission.
            • Notifications & exact alarms — used only to deliver event reminders you schedule.

            AI assistant
            On supported devices, prompts are processed with Gemini Nano on-device. If on-device AI is unavailable, Meridian may send your prompt to Google’s cloud Gemini service as a fallback. Do not include sensitive information in prompts when cloud fallback may apply.

            Analytics & accounts
            Meridian does not require an account. We do not sell your personal data. Firebase/Google SDKs bundled with the app may collect limited diagnostic or crash data according to Google’s policies.

            Your choices
            You can revoke permissions at any time in Android system settings. Deleting the app removes local Meridian data from your device.

            Questions
            Use “Send feedback” in Settings to reach the development team.

            Last updated: $LEGAL_LAST_UPDATED
        """.trimIndent(),
        externalUrl = SettingsUrls.GEMINI_APPS_PRIVACY,
        externalLabel = "Gemini app privacy help",
    ),
    TERMS(
        title = "Terms of use",
        body = """
            By using Meridian you agree to these terms.

            The app
            Meridian provides world-time displays, multi-zone planning tools, reminders, and optional AI-assisted scheduling. Features may change or be removed as the product evolves.

            Acceptable use
            Use Meridian lawfully and do not attempt to reverse engineer, disrupt, or misuse the service. You are responsible for the accuracy of calendar events, invites, and reminders you create.

            No warranty
            Meridian is provided “as is” without warranties of any kind. Time-zone data, solar calculations, and AI suggestions are informational — always verify critical scheduling decisions independently.

            Limitation of liability
            To the fullest extent permitted by law, the developers are not liable for missed meetings, incorrect time conversions, data loss, or indirect damages arising from use of the app.

            Third-party services
            Cloud AI fallback, Google Play services, and device platform APIs are subject to their own terms. Your use of those features is also governed by the applicable provider agreements.

            Changes
            These terms may be updated in future releases. Continued use after an update constitutes acceptance of the revised terms.

            Last updated: $LEGAL_LAST_UPDATED
        """.trimIndent(),
    ),
    DATA_HANDLING(
        title = "How your data is handled",
        body = """
            Stored on your device
            • Pinned and saved time zones
            • Home location and home-country anchors
            • Planner participants, working hours, and preferences
            • App appearance and reminder settings

            Processed on your device
            • Time-zone math, fairness scoring, and solar calculations
            • On-device Gemini Nano inference when hardware supports it

            May leave your device
            • Cloud Gemini requests when on-device AI is unavailable
            • Standard Android/Google SDK telemetry, if enabled on your device
            • Calendar .ics files or share sheets you explicitly trigger

            Not collected by Meridian
            • No Meridian login or cloud profile
            • No upload of your full contact list or calendar by default
            • No sale of personal information

            Retention
            Data remains on your device until you clear app storage or uninstall Meridian.

            Last updated: $LEGAL_LAST_UPDATED
        """.trimIndent(),
    ),
    OPEN_SOURCE(
        title = "Open source licenses",
        body = """
            Meridian is built with open-source software. Key components include:

            • Jetpack Compose & AndroidX (Apache 2.0)
            • Kotlin & kotlinx libraries (Apache 2.0)
            • Material Symbols (Apache 2.0)
            • Haze — Chris Banes (Apache 2.0)
            • Room, DataStore, Navigation, Glance, WorkManager (Apache 2.0)
            • Firebase Android SDK & Firebase AI Logic (Google terms apply)
            • Roborazzi testing tools (Apache 2.0)

            Full license texts are available in the respective project repositories. Source code for Meridian itself is maintained by the project authors.

            Last updated: $LEGAL_LAST_UPDATED
        """.trimIndent(),
    ),
    THIRD_PARTY_POLICIES(
        title = "Third-party policies",
        body = """
            Meridian embeds Google platform services. When you use cloud AI fallback or Firebase-backed features, those providers’ policies also apply.

            Review the current policies at the links below. Meridian does not control third-party data practices.
        """.trimIndent(),
    ),
}
