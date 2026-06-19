package com.example.core.time

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.text.Normalizer
import java.util.Locale

/**
 * Comprehensive offline city + airport → IANA-zone lookup, backing "every city" location search.
 *
 * The data lives in a prebuilt SQLite database bundled at `assets/cities.db` (~211k cities from
 * GeoNames + ~5.5k airports from OpenFlights; see `tools/citygen/`). It is far too large to keep on
 * the heap, so on first use the asset is extracted once to no-backup storage and opened read-only;
 * queries are indexed prefix scans run off the main thread. It complements [PlaceIndex] (which keeps
 * curated friendly names/aliases for the most common places) — this fills in the long tail.
 *
 * All lookups fail soft: any I/O or query error yields an empty list so search still works via the
 * curated index and raw IANA ids.
 */
class GeoPlaceRepository(private val appContext: Context) {

    private val mutex = Mutex()
    @Volatile private var db: SQLiteDatabase? = null
    @Volatile private var unavailable = false

    /** Cities whose [ZoneMatch.displayName] is the city name, best (most populous) first. */
    suspend fun searchCities(query: String, limit: Int): List<ZoneMatch> {
        val folded = fold(query)
        if (folded.isEmpty() || limit <= 0) return emptyList()
        val handle = database() ?: return emptyList()
        val prefix = escapeLike(folded) + "%"
        return withContext(Dispatchers.IO) {
            runCatching {
                // name_lower folds the native name ("Zürich"->"zurich"); ascii_lower covers the
                // GeoNames romanization ("Zuerich", or "Tokyo" for native scripts) when it differs.
                handle.rawQuery(
                    "SELECT name, zone FROM city " +
                        "WHERE name_lower LIKE ? ESCAPE '\\' OR ascii_lower LIKE ? ESCAPE '\\' " +
                        "ORDER BY population DESC LIMIT $limit",
                    arrayOf(prefix, prefix),
                ).use { c ->
                    buildList { while (c.moveToNext()) add(ZoneMatch(c.getString(1), c.getString(0))) }
                }
            }.getOrDefault(emptyList())
        }
    }

    /**
     * Airports by IATA code (exact match first, then prefix) and by airport name (substring), so
     * "SFO", "lhr", or "heathrow" (mid-name in "London Heathrow Airport") all resolve.
     * [ZoneMatch.displayName] is "City (IATA)", e.g. "London (LHR)".
     */
    suspend fun searchAirports(query: String, limit: Int): List<ZoneMatch> {
        val folded = fold(query)
        if (folded.isEmpty() || limit <= 0) return emptyList()
        val handle = database() ?: return emptyList()
        val escaped = escapeLike(folded)
        val prefix = "$escaped%"
        val contains = "%$escaped%"
        return withContext(Dispatchers.IO) {
            runCatching {
                handle.rawQuery(
                    "SELECT iata, city, zone FROM airport " +
                        "WHERE iata_lower = ? OR iata_lower LIKE ? ESCAPE '\\' OR name_lower LIKE ? ESCAPE '\\' " +
                        "ORDER BY (iata_lower = ?) DESC, length(iata_lower), iata_lower, name LIMIT $limit",
                    arrayOf(folded, prefix, contains, folded),
                ).use { c ->
                    buildList {
                        while (c.moveToNext()) {
                            add(ZoneMatch(c.getString(2), "${c.getString(1)} (${c.getString(0)})"))
                        }
                    }
                }
            }.getOrDefault(emptyList())
        }
    }

    /** Eagerly extract + open the database (e.g. at app start) so the first search is instant. */
    suspend fun prewarm() { database() }

    private suspend fun database(): SQLiteDatabase? {
        db?.let { return it }
        if (unavailable) return null
        return withContext(Dispatchers.IO) {
            mutex.withLock {
                db?.let { return@withLock it }
                val opened = runCatching { prepare() }.getOrNull()
                if (opened == null) unavailable = true
                db = opened
                opened
            }
        }
    }

    /** Extract the asset if missing or stale, then open it read-only. */
    private fun prepare(): SQLiteDatabase {
        val target = File(appContext.noBackupFilesDir, DB_NAME)
        if (!target.exists()) extractAsset(target)
        var opened = openReadOnly(target)
        if (readVersion(opened) != EXPECTED_VERSION) {
            opened.close()
            extractAsset(target)
            opened = openReadOnly(target)
        }
        return opened
    }

    private fun openReadOnly(file: File): SQLiteDatabase =
        SQLiteDatabase.openDatabase(file.absolutePath, null, SQLiteDatabase.OPEN_READONLY)

    private fun extractAsset(target: File) {
        target.parentFile?.mkdirs()
        val tmp = File(target.parentFile, "$DB_NAME.tmp")
        appContext.assets.open(DB_NAME).use { input ->
            tmp.outputStream().use { output -> input.copyTo(output) }
        }
        if (target.exists()) target.delete()
        check(tmp.renameTo(target)) { "Could not move extracted $DB_NAME into place" }
    }

    private fun readVersion(database: SQLiteDatabase): Int = runCatching {
        database.rawQuery("SELECT version FROM schema_meta LIMIT 1", null).use { c ->
            if (c.moveToFirst()) c.getInt(0) else -1
        }
    }.getOrDefault(-1)

    private companion object {
        const val DB_NAME = "cities.db"
        const val EXPECTED_VERSION = 2 // must match BUNDLE_VERSION in tools/citygen/build_cities_db.py

        /** Lowercase + strip diacritics so "Zürich" matches the ASCII-folded `name_lower` column. */
        fun fold(query: String): String {
            val trimmed = query.trim()
            if (trimmed.isEmpty()) return ""
            val decomposed = Normalizer.normalize(trimmed, Normalizer.Form.NFD)
            return decomposed.replace(Regex("\\p{Mn}+"), "").lowercase(Locale.ROOT)
        }

        /** Escape SQLite LIKE wildcards so a literal query can't act as a pattern. */
        fun escapeLike(s: String): String =
            s.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    }
}
