// GeoPlaceRepository.swift
// Meridian — iOS 27+ / Swift 6
//
// Ported from app/src/main/java/com/example/core/time/GeoPlaceRepository.kt

import Foundation
import SQLite3

/// Comprehensive offline city + airport → IANA-zone lookup, backing "every city" location search.
///
/// The data lives in a prebuilt SQLite database bundled in the app as `cities.db` (~211k cities from
/// GeoNames + ~5.5k airports from OpenFlights; see `tools/citygen/`). It complements ``PlaceIndex``
/// (curated friendly names/aliases for the most common places) — this fills in the long tail.
///
/// All lookups fail soft: any I/O or query error yields an empty list so search still works via the
/// curated index and raw IANA ids. If the DB is not bundled, every query returns `[]`.
///
/// ## Bundling
/// Ship `cities.db` as a resource in the app target (Build Phases → Copy Bundle Resources, or a
/// Resources group in SwiftPM). On iOS the bundle is read-only, and SQLite can open a read-only
/// database directly from the bundle path, so — unlike Android — no extract-to-writable-storage step
/// is needed. The schema must expose a `schema_meta(version)` row matching ``expectedVersion`` plus
/// `city(name, name_lower, ascii_lower, zone, population)` and
/// `airport(iata, iata_lower, city, name, name_lower, zone)`.
public actor GeoPlaceRepository {

    public static let shared = GeoPlaceRepository()

    private var handle: OpaquePointer?
    private var prepared = false
    private var unavailable = false

    private let dbName: String
    private let bundle: Bundle

    /// - Parameters:
    ///   - dbName: Resource name (without extension) of the bundled database. Default `"cities"`.
    ///   - bundle: Bundle to load the resource from. Default `.main`.
    public init(dbName: String = "cities", bundle: Bundle = .main) {
        self.dbName = dbName
        self.bundle = bundle
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    // MARK: - Public API

    /// Cities whose ``ZoneMatch/displayName`` is the city name, best (most populous) first.
    public func searchCities(query: String, limit: Int) -> [ZoneMatch] {
        let folded = Self.fold(query)
        if folded.isEmpty || limit <= 0 { return [] }
        guard let db = database() else { return [] }
        let prefix = Self.escapeLike(folded) + "%"

        // name_lower folds the native name ("Zürich"->"zurich"); ascii_lower covers the GeoNames
        // romanization ("Zuerich", or "Tokyo" for native scripts) when it differs.
        let sql = """
        SELECT name, zone FROM city \
        WHERE name_lower LIKE ? ESCAPE '\\' OR ascii_lower LIKE ? ESCAPE '\\' \
        ORDER BY population DESC LIMIT ?
        """
        return query(db, sql) { stmt in
            Self.bindText(stmt, 1, prefix)
            Self.bindText(stmt, 2, prefix)
            sqlite3_bind_int(stmt, 3, Int32(limit))
        } row: { stmt in
            guard let name = Self.columnText(stmt, 0), let zone = Self.columnText(stmt, 1) else { return nil }
            return ZoneMatch(zoneId: zone, displayName: name)
        }
    }

    /// Airports by IATA code (exact match first, then prefix) and by airport name (substring), so
    /// "SFO", "lhr", or "heathrow" (mid-name in "London Heathrow Airport") all resolve.
    /// ``ZoneMatch/displayName`` is "City (IATA)", e.g. "London (LHR)".
    public func searchAirports(query: String, limit: Int) -> [ZoneMatch] {
        let folded = Self.fold(query)
        if folded.isEmpty || limit <= 0 { return [] }
        guard let db = database() else { return [] }
        let escaped = Self.escapeLike(folded)
        let prefix = "\(escaped)%"
        let contains = "%\(escaped)%"

        let sql = """
        SELECT iata, city, zone FROM airport \
        WHERE iata_lower = ? OR iata_lower LIKE ? ESCAPE '\\' OR name_lower LIKE ? ESCAPE '\\' \
        ORDER BY (iata_lower = ?) DESC, length(iata_lower), iata_lower, name LIMIT ?
        """
        return query(db, sql) { stmt in
            Self.bindText(stmt, 1, folded)
            Self.bindText(stmt, 2, prefix)
            Self.bindText(stmt, 3, contains)
            Self.bindText(stmt, 4, folded)
            sqlite3_bind_int(stmt, 5, Int32(limit))
        } row: { stmt in
            guard let iata = Self.columnText(stmt, 0),
                  let city = Self.columnText(stmt, 1),
                  let zone = Self.columnText(stmt, 2) else { return nil }
            return ZoneMatch(zoneId: zone, displayName: "\(city) (\(iata))")
        }
    }

    /// Eagerly open the database (e.g. at app start) so the first search is instant.
    public func prewarm() {
        _ = database()
    }

    // MARK: - Database lifecycle

    private func database() -> OpaquePointer? {
        if let handle { return handle }
        if prepared || unavailable { return nil }
        prepared = true
        guard let opened = prepare() else {
            unavailable = true
            return nil
        }
        handle = opened
        return opened
    }

    private func prepare() -> OpaquePointer? {
        // VERIFY: bundled resource lookup. `cities.db` must be in Copy Bundle Resources.
        guard let path = bundle.path(forResource: dbName, ofType: "db") else { return nil }
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
        guard rc == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return nil
        }
        if readVersion(db) != Self.expectedVersion {
            sqlite3_close(db)
            return nil
        }
        return db
    }

    private func readVersion(_ db: OpaquePointer) -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT version FROM schema_meta LIMIT 1", -1, &stmt, nil) == SQLITE_OK else {
            return -1
        }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : -1
    }

    /// Prepare `sql`, bind via `bind`, then collect every row via `row` (skipping nil results).
    /// Any failure yields `[]`.
    private func query(
        _ db: OpaquePointer,
        _ sql: String,
        bind: (OpaquePointer?) -> Void,
        row: (OpaquePointer?) -> ZoneMatch?
    ) -> [ZoneMatch] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        bind(stmt)
        var results: [ZoneMatch] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let match = row(stmt) { results.append(match) }
        }
        return results
    }

    // MARK: - Helpers

    private static let expectedVersion = 2 // must match BUNDLE_VERSION in tools/citygen/build_cities_db.py

    /// SQLite requires that text bound with a Swift `String` be copied, since the buffer is transient.
    // VERIFY: SQLITE_TRANSIENT is not surfaced by the Swift `SQLite3` overlay; it is the sentinel
    // `-1` cast to the destructor function pointer type, the standard workaround.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, transient)
    }

    private static func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }

    /// Lowercase + strip diacritics so "Zürich" matches the ASCII-folded `name_lower` column.
    static func fold(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        // NFD decomposition then drop combining marks (Unicode general category Mn).
        let decomposed = trimmed.decomposedStringWithCanonicalMapping
        let stripped = decomposed.unicodeScalars.filter { scalar in
            scalar.properties.generalCategory != .nonspacingMark
        }
        return String(String.UnicodeScalarView(stripped)).lowercased()
    }

    /// Escape SQLite LIKE wildcards so a literal query can't act as a pattern.
    static func escapeLike(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
