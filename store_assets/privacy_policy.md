# Meridian — Privacy Policy

**Effective date:** June 18, 2026  
**Package:** `com.Meridian.VBCR`

> Meridian is a timezone and world clock app with AI-powered meeting planning. We collect very little data, no account is required, and we do not sell or monetize your information.

---

## 1. Who We Are

Meridian is an independent Android app developed by a solo developer, published on the Google Play Store. Contact: [bharath.vbcr@gmail.com](mailto:bharath.vbcr@gmail.com)

Meridian is a sibling app to **ChronosFlow** — both apps are developed and signed by the same developer. If you have ChronosFlow installed, Meridian can share task and event data with it on-device (see Section 4).

---

## 2. What Data We Collect

| Data type | Where it goes |
|-----------|---------------|
| **Calendar events** (`READ_CALENDAR` / `WRITE_CALENDAR`) | On-device only — read from and written to your local calendar. Never transmitted to our servers. |
| **AI queries** (text typed in the AI tab) | Processed on-device via Gemini Nano first. If unavailable, sent to Google's servers via Firebase AI Logic. Meridian does not store your queries. |
| **Timezone / city selections** | Stored in app preferences on your device only. Never transmitted. |
| **Meeting plans** | Stored locally. Optionally exported to your calendar or shared with ChronosFlow. |
| **Location / GPS** | **Not collected.** Meridian never requests location permission — you manually pick cities and timezones. |
| **Account / personal identity** | **Not collected.** No account, registration, email, or name is ever requested. |
| **Crash & performance telemetry** | Collected automatically by Firebase (anonymized). See Section 4. |
| **Advertising identifiers** | **Not collected.** Meridian contains no advertising SDKs. |

---

## 3. How We Use the Data

Data is used solely to provide app functionality:

- **Calendar access** — to display your existing events alongside world clocks and to create meeting events when you save a plan.
- **AI queries** — to generate responses in the AI assistant tab. Queries are processed transiently and are not used to train models or build profiles.
- **Timezone selections** — to remember your pinned clocks across app sessions.
- **Crash data (Firebase)** — to identify and fix bugs so the app works reliably.

We do not use any data for advertising, profiling, or sale to third parties.

---

## 4. Data Sharing and Third Parties

### Google / Firebase

- **Firebase AI Logic (Gemini cloud fallback)** — when on-device AI is unavailable, your AI query text is sent to Google's servers to generate a response. Google may retain this data subject to their own privacy policies.
- **Firebase Crashlytics / Performance Monitoring** — automatically collects anonymized crash reports and performance metrics. No personally identifiable information is attached.

Google's privacy practices: [policies.google.com/privacy](https://policies.google.com/privacy)

### ChronosFlow (Sibling App)

If ChronosFlow (same developer) is installed, Meridian can share task and calendar event data with it via a local Android ContentProvider. This sharing:

- Only occurs if ChronosFlow is installed and both apps share the same developer signing key.
- Happens entirely on-device — no data leaves your device.
- Is limited to meeting/event records you create in Meridian.

### No Other Sharing

We do not share your data with any analytics companies, advertisers, data brokers, or any third party not listed above. We do not sell your data.

---

## 5. Android Permissions Explained

| Permission | Why it is needed |
|------------|-----------------|
| `READ_CALENDAR` | Displays your existing calendar events alongside world clocks and meeting plans. |
| `WRITE_CALENDAR` | Creates new calendar events when you save a meeting plan. |
| `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` | Fires precise reminders for scheduled meetings at the exact time you specify. |
| `RECEIVE_BOOT_COMPLETED` | Restores scheduled alarms after a device restart so reminders are not lost. |
| Wear OS / Companion permissions | Syncs world clock data to the Wear OS companion app. |

---

## 6. Data Retention

Meridian does not maintain a backend database. All user-generated data (timezone selections, pinned clocks, saved meeting plans) is stored locally on your device and retained only as long as the app is installed.

- **Calendar events** you asked Meridian to create are stored in your device's calendar app and managed by you directly.
- **Firebase crash/performance data** is retained by Google per their standard Firebase data retention policies.
- **AI query text** sent to Google's cloud is handled under Google's privacy policy and is not retained by Meridian.

---

## 7. Your Rights and Choices

- **Delete all app data:** Uninstall Meridian — this removes all locally stored preferences, pinned clocks, and cached data.
- **Revoke calendar access:** Go to *Settings → Apps → Meridian → Permissions* and revoke the Calendar permission at any time.
- **Delete calendar events:** Events created by Meridian can be deleted directly in your calendar app.
- **Firebase data:** Refer to [Google's Privacy Policy](https://policies.google.com/privacy) for requests related to data held by Google/Firebase.
- **Contact us:** Email [bharath.vbcr@gmail.com](mailto:bharath.vbcr@gmail.com) with any privacy-related requests.

---

## 8. Children's Privacy

Meridian is not directed at children under the age of 13. We do not knowingly collect personal information from children under 13. If you believe a child under 13 has provided information through this app, please contact us at [bharath.vbcr@gmail.com](mailto:bharath.vbcr@gmail.com).

---

## 9. Security

Meridian stores user data only on-device, protected by Android's sandbox and your device's encryption. AI queries sent to Google's cloud are transmitted over HTTPS. We do not operate servers that store your personal data.

---

## 10. Changes to This Policy

If we make material changes to this Privacy Policy, we will update the effective date at the top of this page. Continued use of Meridian after a change constitutes acceptance of the updated policy.

---

## 11. Contact Us

**Meridian App — Developer Contact**  
Email: [bharath.vbcr@gmail.com](mailto:bharath.vbcr@gmail.com)

We aim to respond to all privacy-related inquiries within 7 business days.

---

*© 2026 Meridian | Privacy Policy | Effective June 18, 2026*
