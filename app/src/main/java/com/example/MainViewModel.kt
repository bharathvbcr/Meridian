package com.example

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.example.core.data.SavedZone
import com.example.core.data.ZoneAnchorRole
import com.example.core.data.isNowAnchor
import com.example.core.data.PlannedTask
import com.example.core.data.Person
import com.example.core.data.MeridianSettings
import com.example.core.data.HourCycle
import com.example.core.time.TimeEngine
import com.example.core.time.FindOverlapUseCase
import com.example.core.time.MeetingParticipant
import com.example.core.time.OffsetZones
import com.example.core.time.PlaceIndex
import com.example.core.time.TzAbbreviations
import com.example.core.ai.GeminiRepository
import com.example.core.ai.MeridianAiTools
import com.example.core.ai.AiResult
import com.example.feature.calendar.CalendarEvent
import com.example.feature.calendar.CalendarRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.datetime.toJavaInstant
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.Locale

/** [onDevice] tags an assistant reply with where it ran (true = Gemini Nano, false = cloud); null when N/A. */
data class ChatMessage(
    val id: Long,
    val sender: String,
    val text: String,
    val isUser: Boolean,
    val onDevice: Boolean? = null,
)

/** How many airport matches a single search may contribute, so they never crowd out cities. */
private const val AIRPORT_RESULT_LIMIT = 6

class MainViewModel(
    application: Application,
    private val timeEngine: TimeEngine
) : AndroidViewModel(application) {

    val scrubInstant: StateFlow<Instant?> = timeEngine.scrubInstant

    private val container = (application as MeridianApplication).container
    private val zoneDao = container.zoneDao
    private val taskDao = container.taskDao
    private val personDao = container.personDao
    private val settingsRepository = container.settingsRepository
    private val reminderScheduler = container.reminderScheduler
    private val locationZoneResolver = container.locationZoneResolver
    private val geoPlaceRepository = container.geoPlaceRepository
    val findOverlapUseCase: FindOverlapUseCase = container.findOverlapUseCase

    // The assistant resolves places through the same multi-layer search the add-a-zone UI uses, and
    // reads "now" from the shared TimeEngine, so its live answers match the rest of the app (§12.7).
    private val geminiRepository = GeminiRepository(
        MeridianAiTools(
            resolvePlace = { query -> searchTimeZones(query).firstOrNull() },
            findOverlap = findOverlapUseCase,
            now = { timeEngine.now() },
        )
    )

    val settings: StateFlow<MeridianSettings> = settingsRepository.settings
        .stateIn(viewModelScope, SharingStarted.Eagerly, MeridianSettings())

    val savedZones: StateFlow<List<SavedZone>> = zoneDao.getAllZones()
        .stateIn(viewModelScope, SharingStarted.Lazily, emptyList())

    val plannedTasks: StateFlow<List<PlannedTask>> = taskDao.getAllTasks()
        .stateIn(viewModelScope, SharingStarted.Lazily, emptyList())

    val people: StateFlow<List<Person>> = personDao.getAllPeople()
        .stateIn(viewModelScope, SharingStarted.Lazily, emptyList())

    private var nextChatMessageId = 0L

    private fun chatMessage(
        sender: String,
        text: String,
        isUser: Boolean,
        onDevice: Boolean? = null,
    ) = ChatMessage(
        id = nextChatMessageId++,
        sender = sender,
        text = text,
        isUser = isUser,
        onDevice = onDevice,
    )

    private val welcomeMessage = chatMessage(
        "Meridian Assistant",
        "Hello! I'm Meridian. I can tell you the real current time anywhere, convert times between " +
            "cities, find fair meeting windows, and schedule events across time zones — on-device when " +
            "your phone supports it, with cloud backup otherwise. Try \"What time is it in Tokyo right now?\"",
        false,
    )
    private val _chatMessages = MutableStateFlow(listOf(welcomeMessage))
    val chatMessages: StateFlow<List<ChatMessage>> = _chatMessages.asStateFlow()

    private val _aiLoading = MutableStateFlow(false)
    val aiLoading: StateFlow<Boolean> = _aiLoading.asStateFlow()

    // A model-proposed event awaiting explicit user confirmation before any write (§12.8).
    private val _pendingDraft = MutableStateFlow<PlannedTask?>(null)
    val pendingDraft: StateFlow<PlannedTask?> = _pendingDraft.asStateFlow()

    private val _calendarEvents = MutableStateFlow<List<CalendarEvent>>(emptyList())
    val calendarEvents: StateFlow<List<CalendarEvent>> = _calendarEvents.asStateFlow()

    // Full searchable lists of IANA TimeZones
    private val availableZoneIds = ZoneId.getAvailableZoneIds().sorted()

    init {
        // Extract + open the bundled city/airport database up front so the first search is instant.
        viewModelScope.launch { runCatching { geoPlaceRepository.prewarm() } }
        viewModelScope.launch {
            // Check if db is empty and insert initial values
            zoneDao.getAllZones().collect { zones ->
                if (zones.isEmpty()) {
                    zoneDao.insertZone(SavedZone("Europe/London", "London", orderIndex = 0))
                    zoneDao.insertZone(SavedZone("Asia/Tokyo", "Tokyo", orderIndex = 1))
                    zoneDao.insertZone(SavedZone("America/New_York", "New York", orderIndex = 2))
                } else {
                    container.wearSyncManager.syncZones(zones)
                }
            }
        }
    }

    fun selectScrubTime(instant: Instant?) {
        timeEngine.updateScrub(instant)
    }

    /**
     * Deterministically ranks meeting slots for the given participants (each with their own
     * working/DND window) on a base date. Pure delegation to [FindOverlapUseCase] — the LLM never
     * computes time (§12.7). Participants with invalid zone ids are dropped defensively.
     */
    fun computeMeetingSlots(
        participants: List<MeetingParticipant>,
        baseDateInstant: Instant
    ): List<FindOverlapUseCase.OverlapSlot> {
        val valid = participants.filter { runCatching { kotlinx.datetime.TimeZone.of(it.zoneId) }.isSuccess }
        if (valid.isEmpty()) return emptyList()
        return findOverlapUseCase.rankParticipantSlots(
            timeEngine.javaToKotlinInstant(baseDateInstant),
            valid
        )
    }

    /**
     * Creates a rotating weekly series from ranked [slots]: week N uses the Nth rotation pick
     * (a fairer-for-different-regions time) shifted forward N weeks, saved as plan drafts (§5.8).
     */
    fun createRotatingSeries(
        slots: List<FindOverlapUseCase.OverlapSlot>,
        weeks: Int,
        zoneId: String
    ) {
        val picks = com.example.core.time.RotationPlanner.rotatingSeries(slots, weeks)
        picks.forEachIndexed { index, slot ->
            val instant = slot.utcStartInstant.toJavaInstant().plusSeconds(index * 7L * 24 * 3600)
            addTask(
                PlannedTask(
                    title = "Rotating sync (week ${index + 1})",
                    timestamp = instant.toEpochMilli(),
                    zoneId = zoneId,
                )
            )
        }
    }

    fun setHourCycle(cycle: HourCycle) {
        viewModelScope.launch { settingsRepository.setHourCycle(cycle) }
    }

    fun setGlassEnabled(enabled: Boolean) {
        viewModelScope.launch { settingsRepository.setGlassEnabled(enabled) }
    }

    fun setReduceTransparency(enabled: Boolean) {
        viewModelScope.launch { settingsRepository.setReduceTransparency(enabled) }
    }

    fun setBackdropEnabled(enabled: Boolean) {
        viewModelScope.launch { settingsRepository.setBackdropEnabled(enabled) }
    }

    fun setBackdropIntensity(percent: Int) {
        viewModelScope.launch { settingsRepository.setBackdropIntensity(percent) }
    }

    fun setGlassOpacity(percent: Int) {
        viewModelScope.launch { settingsRepository.setGlassOpacity(percent) }
    }

    fun setReminderLeadMinutes(minutes: Int) {
        viewModelScope.launch { settingsRepository.setReminderLeadMinutes(minutes) }
    }

    fun setDefaultWorkStartHour(hour: Int) {
        viewModelScope.launch { settingsRepository.setDefaultWorkStartHour(hour) }
    }

    fun setDefaultWorkEndHour(hour: Int) {
        viewModelScope.launch { settingsRepository.setDefaultWorkEndHour(hour) }
    }

    fun setMapStyle(style: com.example.core.data.MapStyle) {
        viewModelScope.launch { settingsRepository.setMapStyle(style) }
    }

    fun setHomeCountryEnabled(enabled: Boolean) {
        viewModelScope.launch { settingsRepository.setHomeCountryEnabled(enabled) }
    }

    /**
     * Resolves [query] to addable zones across every supported dimension — zone, UTC offset, city,
     * and airport — merged by priority and deduped by zone id (so the same zone never appears twice):
     *
     *  1. UTC/GMT offsets ("UTC", "gmt+1", "utc+5:30", "-0800").
     *  2. Curated [PlaceIndex] — friendly names, aliases, and airport codes for the most common cities.
     *  3. The comprehensive bundled city database (~211k world cities/towns) via [geoPlaceRepository].
     *  4. Airports by IATA code or name ("SFO", "lhr", "heathrow").
     *  5. Raw IANA ids, so even obscure zones stay reachable by their identifier.
     *
     * Suspends because (3) and (4) read a bundled SQLite database off the main thread.
     */
    suspend fun searchTimeZones(query: String): List<SavedZone> {
        if (query.isBlank()) return emptyList()
        val limit = 10
        // Preserve the priority order layers contribute in, while collapsing duplicate zones.
        val merged = LinkedHashMap<String, SavedZone>()
        fun offer(zoneId: String, displayName: String) {
            if (merged.size < limit) merged.putIfAbsent(zoneId, SavedZone(id = zoneId, displayName = displayName))
        }

        OffsetZones.parse(query).forEach { offer(it.zoneId, it.displayName) }
        TzAbbreviations.resolve(query)?.let { offer(it.zoneId, it.displayName) }
        PlaceIndex.search(query, limit).forEach { offer(it.zoneId, it.city) }
        if (merged.size < limit) {
            geoPlaceRepository.searchCities(query, limit).forEach { offer(it.zoneId, it.displayName) }
        }
        if (merged.size < limit) {
            geoPlaceRepository.searchAirports(query, AIRPORT_RESULT_LIMIT).forEach { offer(it.zoneId, it.displayName) }
        }
        if (merged.size < limit) {
            val lower = query.lowercase(Locale.ROOT)
            for (id in availableZoneIds) {
                if (merged.size >= limit) break
                if (id.lowercase(Locale.ROOT).contains(lower)) {
                    offer(id, id.substringAfterLast('/').replace('_', ' '))
                }
            }
        }
        return merged.values.toList()
    }

    fun addZone(zone: SavedZone) {
        viewModelScope.launch {
            val zones = savedZones.value
            val existing = zones.find { it.id == zone.id }
            val maxOrder = zones.maxOfOrNull { it.orderIndex } ?: 0
            val toInsert = when {
                existing != null -> existing.copy(
                    displayName = zone.displayName.ifBlank { existing.displayName },
                    isFavorite = existing.isFavorite || zone.isFavorite,
                )
                else -> zone.copy(
                    orderIndex = if (zone.orderIndex == 0) maxOrder + 1 else zone.orderIndex,
                )
            }
            zoneDao.insertZone(toInsert)
        }
    }

    fun removeZone(zoneId: String) {
        viewModelScope.launch {
            zoneDao.deleteZone(zoneId)
        }
    }

    /** Marks [zoneId] as the home anchor (usual base) and clears the flag on all others. */
    fun setHomeZone(zoneId: String, displayName: String? = null) {
        setAnchorZone(zoneId, displayName, ZoneAnchorRole.RESIDENCE)
    }

    /**
     * Pins [zoneId] to an anchor slot on the Now card ([ZoneAnchorRole.HOME_COUNTRY] or
     * [ZoneAnchorRole.RESIDENCE]), replacing any zone already in that slot.
     */
    fun setAnchorZone(zoneId: String, displayName: String?, anchorRole: String) {
        if (anchorRole.isBlank()) return
        viewModelScope.launch {
            val zones = savedZones.value
            val name = displayName ?: zoneId.substringAfterLast('/').replace('_', ' ')
            if (zones.none { it.id == zoneId }) {
                zoneDao.insertZone(
                    SavedZone(
                        id = zoneId,
                        displayName = name,
                        isHome = anchorRole == ZoneAnchorRole.RESIDENCE,
                        anchorRole = anchorRole,
                        orderIndex = 0,
                    )
                )
            }
            zones.forEach { zone ->
                when {
                    zone.id == zoneId -> zoneDao.insertZone(
                        zone.copy(
                            displayName = name,
                            anchorRole = anchorRole,
                            isHome = anchorRole == ZoneAnchorRole.RESIDENCE,
                            orderIndex = 0,
                        )
                    )
                    zone.anchorRole == anchorRole -> zoneDao.insertZone(
                        zone.copy(
                            anchorRole = ZoneAnchorRole.NONE,
                            isHome = false,
                        )
                    )
                }
            }
            if (anchorRole == ZoneAnchorRole.HOME_COUNTRY) {
                settingsRepository.setHomeCountryEnabled(true)
            }
        }
    }

    fun addPerson(
        name: String,
        zoneId: String,
        locationName: String = "",
        workStartHour: Int = 9,
        workEndHour: Int = 17,
        dndStartHour: Int = -1,
        dndEndHour: Int = -1,
        isFavorite: Boolean = false,
    ) {
        if (zoneId.isBlank()) return
        viewModelScope.launch {
            personDao.insertPerson(
                Person(
                    name = name.trim(),
                    zoneId = zoneId,
                    locationName = locationName.ifBlank {
                        zoneId.substringAfterLast('/').replace('_', ' ')
                    },
                    workStartHour = workStartHour,
                    workEndHour = workEndHour,
                    dndStartHour = dndStartHour,
                    dndEndHour = dndEndHour,
                    isFavorite = isFavorite,
                )
            )
        }
    }

    fun deletePerson(personId: Int) {
        viewModelScope.launch { personDao.deletePerson(personId) }
    }

    fun togglePersonFavorite(personId: Int, isFavorite: Boolean) {
        viewModelScope.launch { personDao.updateFavorite(personId, isFavorite) }
    }

    fun toggleZoneFavorite(zoneId: String, isFavorite: Boolean) {
        viewModelScope.launch { zoneDao.updateFavorite(zoneId, isFavorite) }
    }

    fun loadCalendarEvents(fromMillis: Long, toMillis: Long) {
        viewModelScope.launch {
            val events = withContext(Dispatchers.IO) {
                CalendarRepository.readEvents(getApplication(), fromMillis, toMillis)
            }
            _calendarEvents.value = events
        }
    }

    fun hasLocationPermission(): Boolean = locationZoneResolver.hasLocationPermission()

    /**
     * Resolves the home zone from the device's last-known location (offline, §5.1) and sets it.
     * Invokes [onResult] with the resolved IANA id, or null if it couldn't be determined.
     */
    fun resolveHomeFromLocation(onResult: (String?) -> Unit) {
        viewModelScope.launch {
            val zoneId = locationZoneResolver.resolveHomeZoneId()
            if (zoneId != null) setAnchorZone(zoneId, null, ZoneAnchorRole.RESIDENCE)
            onResult(zoneId)
        }
    }

    fun addTask(task: PlannedTask) {
        viewModelScope.launch {
            val maxOrder = plannedTasks.value.maxOfOrNull { it.orderIndex } ?: 0
            val taskWithOrder = if (task.orderIndex == 0) task.copy(orderIndex = maxOrder + 1) else task
            val newId = taskDao.insertTask(taskWithOrder).toInt()
            // Schedule a reminder + refresh the live countdown for the freshly persisted task (§5.7).
            reminderScheduler.schedule(taskWithOrder.copy(id = newId))
            com.example.core.notify.LiveUpdates.refreshNow(getApplication())
        }
    }

    fun deleteTask(taskId: Int) {
        viewModelScope.launch {
            reminderScheduler.cancel(taskId)
            taskDao.deleteTask(taskId)
            com.example.core.notify.LiveUpdates.refreshNow(getApplication())
        }
    }

    fun reorderZone(zoneId: String, direction: Int) { // direction: -1 for UP, 1 for DOWN
        viewModelScope.launch {
            val zones = savedZones.value.toMutableList()
            val index = zones.indexOfFirst { it.id == zoneId }
            if (index == -1) return@launch
            val targetIndex = index + direction
            if (targetIndex in zones.indices) {
                val item = zones[index]
                val other = zones[targetIndex]

                val tempOrder = item.orderIndex

                zoneDao.insertZone(item.copy(orderIndex = other.orderIndex))
                zoneDao.insertZone(other.copy(orderIndex = tempOrder))
            }
        }
    }

    fun reorderZones(orderedIds: List<String>) {
        viewModelScope.launch {
            val allZones = savedZones.value
            val anchorZones = allZones.filter { it.isNowAnchor() }
            anchorZones.forEachIndexed { idx, zone ->
                if (zone.orderIndex != idx) {
                    zoneDao.insertZone(zone.copy(orderIndex = idx))
                }
            }
            val anchorCount = anchorZones.size
            orderedIds.forEachIndexed { idx, id ->
                val zone = allZones.find { it.id == id } ?: return@forEachIndexed
                val newIndex = idx + anchorCount
                if (zone.orderIndex != newIndex) {
                    zoneDao.insertZone(zone.copy(orderIndex = newIndex))
                }
            }
        }
    }

    fun reorderTask(taskId: Int, direction: Int) { // direction: -1 for UP, 1 for DOWN
        viewModelScope.launch {
            val tasks = plannedTasks.value.toMutableList()
            val index = tasks.indexOfFirst { it.id == taskId }
            if (index == -1) return@launch
            val targetIndex = index + direction
            if (targetIndex in tasks.indices) {
                val item = tasks[index]
                val other = tasks[targetIndex]
                
                val tempOrder = item.orderIndex
                
                taskDao.insertTask(item.copy(orderIndex = other.orderIndex))
                taskDao.insertTask(other.copy(orderIndex = tempOrder))
            }
        }
    }

    fun sendAiMessage(messageText: String) {
        if (messageText.isBlank()) return
        
        val userMsg = chatMessage("User", messageText, true)
        _chatMessages.value = _chatMessages.value + userMsg
        _aiLoading.value = true

        val homeZoneId = savedZones.value.firstOrNull { it.isHome }?.id ?: ZoneId.systemDefault().id
        viewModelScope.launch {
            when (val result = geminiRepository.processUserPrompt(
                messageText,
                homeZoneId,
                savedZones.value,
                people.value,
            )) {
                is AiResult.Success -> {
                    _chatMessages.value = _chatMessages.value +
                        chatMessage("Meridian Assistant", result.response, false, onDevice = result.onDevice)
                }
                is AiResult.Scheduled -> {
                    // Propose, never auto-write — the user confirms below (§12.8).
                    _pendingDraft.value = result.task
                    _chatMessages.value = _chatMessages.value + chatMessage(
                        "Meridian Assistant",
                        "I drafted '${result.task.title}'. Review and confirm it below to add it.",
                        false,
                        onDevice = result.onDevice,
                    )
                }
                is AiResult.Error -> {
                    _chatMessages.value = _chatMessages.value + chatMessage("System Error", result.message, false)
                }
            }
            _aiLoading.value = false
        }
    }

    /** Resets the conversation back to the initial welcome message and drops any pending draft. */
    fun clearChat() {
        _chatMessages.value = listOf(welcomeMessage)
        _pendingDraft.value = null
    }

    /** Commits the pending AI-proposed draft to the plan after explicit user confirmation. */
    fun confirmDraft() {
        val draft = _pendingDraft.value ?: return
        addTask(draft)
        _pendingDraft.value = null
        _chatMessages.value = _chatMessages.value +
            chatMessage("Meridian Assistant", "Added '${draft.title}' to your plan.", false)
    }

    fun discardDraft() {
        _pendingDraft.value = null
        _chatMessages.value = _chatMessages.value +
            chatMessage("Meridian Assistant", "Discarded the draft.", false)
    }
}

class MainViewModelFactory(
    private val application: Application
) : ViewModelProvider.Factory {
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(MainViewModel::class.java)) {
            val app = application as MeridianApplication
            @Suppress("UNCHECKED_CAST")
            return MainViewModel(application, app.container.timeEngine) as T
        }
        throw IllegalArgumentException("Unknown ViewModel class")
    }
}
