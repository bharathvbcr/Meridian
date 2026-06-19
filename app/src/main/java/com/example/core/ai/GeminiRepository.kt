package com.example.core.ai

import com.example.core.data.PlannedTask
import com.example.core.data.Person
import com.example.core.data.SavedZone
import com.google.firebase.Firebase
import com.google.firebase.ai.GenerativeModel
import com.google.firebase.ai.InferenceMode
import com.google.firebase.ai.InferenceSource
import com.google.firebase.ai.OnDeviceConfig
import com.google.firebase.ai.OnDeviceModelOption
import com.google.firebase.ai.OnDeviceModelStatus
import com.google.firebase.ai.ai
import com.google.firebase.ai.type.Content
import com.google.firebase.ai.type.FunctionResponsePart
import com.google.firebase.ai.type.GenerativeBackend
import com.google.firebase.ai.type.PublicPreviewAPI
import com.google.firebase.ai.type.Tool
import com.google.firebase.ai.type.content
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel as MlKitGenerativeModel
import com.google.mlkit.genai.prompt.ModelPreference
import com.google.mlkit.genai.prompt.ModelReleaseStage
import com.google.mlkit.genai.prompt.PromptPrefix
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import com.google.mlkit.genai.prompt.generationConfig
import com.google.mlkit.genai.prompt.modelConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

sealed class AiResult {
    /** [onDevice] reflects where inference actually ran — true for Gemini Nano, false for cloud. */
    data class Success(val response: String, val onDevice: Boolean) : AiResult()
    data class Scheduled(val task: PlannedTask, val onDevice: Boolean) : AiResult()
    data class Error(val message: String) : AiResult()
}

/**
 * Drives the Meridian assistant through Firebase AI Logic with hybrid (Gemini Nano) inference:
 * [InferenceMode.PREFER_ON_DEVICE] runs the model locally on capable devices; devices without
 * Gemini Nano fall back to cloud inference automatically so the assistant is always reachable.
 *
 * The assistant can answer live questions ("what time is it in Tokyo?") and act on time because it is
 * given the app's own deterministic time tools ([MeridianAiTools], §12.7 — the LLM never computes
 * time). Those reach the model two ways, because the two inference paths differ in capability:
 *
 *  - **On-device** (preferred): ML Kit Prompt API ([Generation]) runs Gemini Nano with **prefix
 *    caching** — the static system instruction is passed as a [PromptPrefix] so the model processes
 *    it once and reuses the cached KV state on every subsequent request, cutting first-token latency
 *    significantly (300-token prefix: ~0.82 s → ~0.45 s on Pixel 9). Gemini Nano drops tools, so
 *    live facts are pre-resolved via [MeridianAiTools.groundingFacts] and injected into the prompt.
 *  - **Cloud fallback**: Firebase AI Logic ([runWithTools]) with function calling; used when no
 *    on-device model reports [FeatureStatus.AVAILABLE].
 *
 * On-device, Gemini Nano ships in more than one build. We try preview (quality) → preview-fast →
 * stable in order via [MLKIT_MODEL_CONFIGS], mirroring [PREFERRED_MODEL_OPTIONS] on the Firebase
 * path. Only the first [FeatureStatus.AVAILABLE] model is used.
 */
@OptIn(PublicPreviewAPI::class)
class GeminiRepository(private val tools: MeridianAiTools) {

    // Tool schemas advertised to the model (used by the cloud path; harmlessly ignored on-device).
    private val functionTools: List<Tool> = listOf(Tool.functionDeclarations(tools.functionDeclarations()))

    // The system instruction is fully static — same text for every request, every user, every session.
    // Building it once here avoids a StringBuilder allocation on every processUserPrompt() call.
    private val systemInstruction: String = buildSystemInstruction()

    // Pre-wrapped prefix for ML Kit. PromptPrefix is a lightweight data holder so constructing it
    // eagerly is safe; reusing the same instance ensures the runtime can identify and hit the cache.
    private val systemPromptPrefix = PromptPrefix(systemInstruction)

    // ML Kit on-device model resolved once per GeminiRepository instance. Prefix caching works by
    // reusing the same GenerativeModel — the runtime stores the KV state on the instance, so creating
    // a new client per request would re-process the prefix every time and defeat the feature.
    private val onDeviceMutex = Mutex()
    @Volatile private var onDeviceResolved = false
    @Volatile private var cachedOnDeviceModel: MlKitGenerativeModel? = null

    // The Firebase model is rebuilt per request because the system instruction is baked into it and
    // must stay in sync — construction is cheap (config wiring, not engine init).
    // PREFER_ON_DEVICE runs Gemini Nano locally when available; falls back to cloud otherwise.
    private fun buildModel(modelOption: OnDeviceModelOption) =
        Firebase.ai(backend = GenerativeBackend.googleAI()).generativeModel(
            modelName = CLOUD_FALLBACK_MODEL,
            tools = functionTools,
            onDeviceConfig = OnDeviceConfig(
                mode = InferenceMode.PREFER_ON_DEVICE,
                modelOption = modelOption,
            ),
            systemInstruction = content { text(systemInstruction) },
        )

    /**
     * Builds the assistant against the first Gemini Nano build that reports
     * [OnDeviceModelStatus.AVAILABLE], trying the preview builds before stable (see
     * [PREFERRED_MODEL_OPTIONS]). If none are ready on-device, returns a preview-configured model and
     * lets [InferenceMode.PREFER_ON_DEVICE] serve the request from the cloud.
     */
    private suspend fun selectModel(): GenerativeModel {
        for (option in PREFERRED_MODEL_OPTIONS) {
            val model = buildModel(option)
            val status = runCatching { model.onDeviceExtension?.checkStatus() }.getOrNull()
            if (status == OnDeviceModelStatus.AVAILABLE) return model
        }
        return buildModel(OnDeviceModelOption.PREVIEW)
    }

    suspend fun processUserPrompt(
        prompt: String,
        homeZoneId: String = ZoneId.systemDefault().id,
        savedZones: List<SavedZone> = emptyList(),
        people: List<Person> = emptyList(),
    ): AiResult = withContext(Dispatchers.IO) {
        val zone = runCatching { ZoneId.of(homeZoneId) }.getOrDefault(ZoneId.systemDefault())
        val currentTime = ZonedDateTime.now(zone)
        val grounding = runCatching {
            tools.buildGrounding(prompt, zone.id, savedZones, people)
        }.getOrDefault(AiGrounding("", AiQueryIntent.GENERAL))
        // The live-clock facts ride in the PROMPT, not the system instruction: on-device Gemini Nano
        // acts on the message text and effectively ignores the system instruction, so facts placed
        // only there never reach it (it then answers "I have no real-time information"). Putting them
        // in the prompt reaches both paths; the cloud path can still call tools for anything more.
        val modelPrompt = buildContextualPrompt(grounding, currentTime, zone, prompt)

        try {
            // On-device path: ML Kit Prompt API with prefix caching. systemPromptPrefix is the
            // cached PromptPrefix (processed once); modelPrompt is the dynamic suffix per request.
            // Falls back to null when no Nano build is available on this device.
            val onDeviceText = tryOnDeviceInference(modelPrompt)
            val (candidateText, onDevice) = if (onDeviceText != null) {
                onDeviceText to true
            } else {
                // Cloud/Firebase fallback: function calling enabled, auto-falls-back to cloud.
                val model = selectModel()
                runWithTools(model, modelPrompt)
                    ?: return@withContext AiResult.Error("No response received from the assistant model.")
            }

            // A schedule request comes back as a JSON block (works on every inference path). The app
            // resolves its date/time itself (§12.7) so a weak on-device model can't pick a wrong time.
            val scheduleJson = ScheduleParser.extractScheduleJson(candidateText)
            if (scheduleJson != null) {
                ScheduleParser.buildScheduledTask(
                    scheduleJson, prompt, currentTime.toInstant(), zone.id,
                    resolveZoneId = { tools.resolveZoneId(it) },
                )?.let { return@withContext AiResult.Scheduled(it, onDevice) }
                // It was a scheduling request but no date/time could be resolved — ask, don't dump JSON.
                val title = ScheduleParser.titleOf(scheduleJson)
                return@withContext AiResult.Success(
                    "Sure — what date and time should I set${title?.let { " for \"$it\"" } ?: ""}?",
                    onDevice,
                )
            }

            AiResult.Success(candidateText, onDevice)
        } catch (e: Exception) {
            AiResult.Error(e.message ?: "Unknown error occurred running the Gemini Nano assistant.")
        }
    }

    /**
     * Resolves the ML Kit on-device model once and caches it. Iterates [MLKIT_MODEL_CONFIGS]
     * (preview → preview-fast → stable) and returns the first [FeatureStatus.AVAILABLE] client, or
     * null if none are available on this device. Subsequent calls return the cached result instantly
     * without re-querying AICore.
     */
    private suspend fun resolveOnDeviceModel(): MlKitGenerativeModel? {
        if (onDeviceResolved) return cachedOnDeviceModel
        return onDeviceMutex.withLock {
            if (onDeviceResolved) return@withLock cachedOnDeviceModel
            cachedOnDeviceModel = MLKIT_MODEL_CONFIGS.firstNotNullOfOrNull { config ->
                val m = Generation.getClient(config)
                m.takeIf { runCatching { m.checkStatus() }.getOrNull() == FeatureStatus.AVAILABLE }
            }
            onDeviceResolved = true
            cachedOnDeviceModel
        }
    }

    /**
     * Tries on-device inference via the ML Kit Prompt API with implicit prefix caching.
     * [systemPromptPrefix] (the static system instruction) is the cached prefix the runtime processes
     * once and reuses; [contextualPrompt] is the dynamic suffix rebuilt per request. Returns the
     * response text, or null if no on-device model is available on this device.
     */
    private suspend fun tryOnDeviceInference(contextualPrompt: String): String? {
        val model = resolveOnDeviceModel() ?: return null
        return runCatching {
            model.generateContent(
                generateContentRequest(TextPart(contextualPrompt)) {
                    promptPrefix = systemPromptPrefix
                }
            ).candidates.firstOrNull()?.text?.trim()?.takeIf { it.isNotEmpty() }
        }.getOrNull()
    }

    /**
     * Sends [prompt], then services every round of tool calls the model makes (cloud function
     * calling) until it produces a plain answer or [MAX_TOOL_TURNS] is reached. Returns the final
     * text paired with whether the whole exchange stayed on-device, or null if no text came back.
     */
    private suspend fun runWithTools(model: GenerativeModel, prompt: String): Pair<String, Boolean>? {
        val chat = model.startChat()
        var response = chat.sendMessage(prompt)
        var usedCloud = response.inferenceSource == InferenceSource.IN_CLOUD

        var turn = 0
        while (response.functionCalls.isNotEmpty() && turn++ < MAX_TOOL_TURNS) {
            // dispatch() is suspend, so build the responses in a plain loop (not a non-suspend map{}).
            val results = ArrayList<FunctionResponsePart>(response.functionCalls.size)
            for (call in response.functionCalls) {
                results += FunctionResponsePart(call.name, tools.dispatch(call))
            }
            response = chat.sendMessage(Content("function", results))
            if (response.inferenceSource == InferenceSource.IN_CLOUD) usedCloud = true
        }

        val text = response.text?.trim().orEmpty()
        return if (text.isEmpty()) null else text to !usedCloud
    }

    private fun buildSystemInstruction(): String {
        return buildString {
            appendLine("You are Meridian, an elegant world-clock and calendar assistant.")
            appendLine("You help with world times, time-zone conversions, fair meeting windows, and scheduling.")
            appendLine()
            appendLine(
                "Each message may begin with a LIVE CLOCK block of authoritative, up-to-the-second " +
                    "real-world times. Treat those as ground truth and answer from them — never reply " +
                    "that you don't have access to real-time information."
            )
            appendLine()
            appendLine("TOOLS (cloud) — call these for any live fact not already given in the message:")
            appendLine("• get_current_time(location) — the real current time at any place.")
            appendLine("• convert_time(time, from_location, to_location) — convert a time between places.")
            appendLine("• find_meeting_time(locations, within_days) — the fairest shared meeting hours.")
            appendLine()
            appendLine("To SCHEDULE or ADD an event, reply with ONLY a JSON object — no prose, no code fences:")
            appendLine("""{"action":"schedule","title":"...","when":"<date & time in plain words>","zoneId":"<place>"}""")
            appendLine("Give the date/time in WORDS (e.g. \"tomorrow 1pm\"); do NOT compute a timestamp — the app resolves it exactly.")
            appendLine("""Example: {"action":"schedule","title":"Lunch with Emma","when":"tomorrow 1pm","zoneId":"Europe/London"}""")
            appendLine()
            append("Otherwise, answer in plain, friendly, accurate text without markdown code fences.")
        }
    }

    /**
     * Front-loads the live-clock facts and the current date/time into the message itself, then the
     * user's question. This is what makes on-device Gemini Nano answer correctly: it acts on the
     * prompt text, so the times must be here rather than (only) in the system instruction. Falls back
     * to the bare prompt if nothing resolved.
     */
    private fun buildContextualPrompt(
        grounding: AiGrounding,
        currentTime: ZonedDateTime,
        zone: ZoneId,
        prompt: String,
    ): String = buildString {
        if (grounding.block.isNotEmpty()) {
            appendLine(grounding.block)
            appendLine()
        }
        appendLine(
            "Current local date/time: ${currentTime.format(DateTimeFormatter.RFC_1123_DATE_TIME)} " +
                "(${zone.id}). Unix epoch now: ${currentTime.toInstant().toEpochMilli()} ms."
        )
        appendLine()
        when (grounding.intent) {
            AiQueryIntent.SCHEDULE -> appendLine(SCHEDULE_PROMPT_RULE)
            AiQueryIntent.MEETING -> appendLine(
                "Answer from MEETING SLOTS when present. Otherwise use LIVE CLOCK and tools. " +
                    "Reply in plain, friendly text — never say you lack real-time information."
            )
            AiQueryIntent.CONVERT -> appendLine(
                "Answer from TIME CONVERSIONS when present. Otherwise use LIVE CLOCK and tools. " +
                    "Reply in plain, friendly text — never say you lack real-time information."
            )
            AiQueryIntent.CURRENT_TIME -> appendLine(
                "Answer directly from LIVE CLOCK. Reply in one or two short sentences — " +
                    "never say you lack real-time information."
            )
            AiQueryIntent.GENERAL -> appendLine(GENERAL_PROMPT_RULE)
        }
        appendLine()
        append(prompt)
    }

    private companion object {
        const val SCHEDULE_PROMPT_RULE =
            "If the request is to schedule or add an event/meeting, reply with ONLY this JSON and " +
                "nothing else: {\"action\":\"schedule\",\"title\":\"…\",\"when\":\"<date and time in " +
                "plain words exactly as the user said, e.g. 'next Monday 2pm' or '2026-06-22 14:00'>\"," +
                "\"zoneId\":\"<the place, e.g. 'Europe/London' or 'Tokyo'>\"}. Do NOT compute a numeric " +
                "timestamp."

        const val GENERAL_PROMPT_RULE =
            "Answer in plain, friendly text using the times above. To schedule, reply with ONLY the " +
                "schedule JSON (no prose). Never say you lack real-time information."
        /**
         * The **cloud** model that hybrid inference falls back to. This string never names the
         * on-device model — on-device is always Gemini Nano, chosen separately via
         * [OnDeviceModelOption] (preview/stable). With [InferenceMode.PREFER_ON_DEVICE] the SDK runs
         * Nano locally when available and only reaches for this cloud model otherwise. (Firebase's
         * own default cloud fallback is also `gemini-2.5-flash-lite`.)
         */
        const val CLOUD_FALLBACK_MODEL = "gemini-2.5-flash-lite"

        /** Safety cap on tool-calling round-trips so a confused model can never loop forever. */
        const val MAX_TOOL_TURNS = 5

        /**
         * On-device Gemini Nano builds to try, in order. Preview first (newer capabilities, what the
         * AICore preview program installs on recent devices), then the stable build as a fallback.
         * Used by the Firebase AI Logic cloud-fallback path ([selectModel]).
         */
        val PREFERRED_MODEL_OPTIONS = listOf(
            OnDeviceModelOption.PREVIEW,
            OnDeviceModelOption.PREVIEW_FAST,
            OnDeviceModelOption.STABLE,
        )

        /**
         * ML Kit Prompt API model configs to try, in order — mirrors [PREFERRED_MODEL_OPTIONS].
         * Preview (quality) → Preview (fast) → Stable. Used by [tryOnDeviceInference].
         */
        val MLKIT_MODEL_CONFIGS = listOf(
            generationConfig { modelConfig = modelConfig { releaseStage = ModelReleaseStage.PREVIEW } },
            generationConfig { modelConfig = modelConfig { releaseStage = ModelReleaseStage.PREVIEW; preference = ModelPreference.FAST } },
            generationConfig { modelConfig = modelConfig { releaseStage = ModelReleaseStage.STABLE } },
        )
    }
}
