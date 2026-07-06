// WatchWidgetStore.swift
// Meridian — watchOS 27 / Swift 6 (watch app + watch widget extension)
//
// Persists the last `WatchSyncPayload` the watch app received over WatchConnectivity
// into the watch-side App Group container, so the watch WIDGET extension (accessory
// complications / Smart Stack) can render the same zones + next event without a live
// phone connection. This is the storage bridge that gives iOS the glanceable surface
// Android ships as `SecondZoneTileService` (which reads `meridian_wear_prefs`).
//
// Compiled into the MeridianWatch app (writer) and MeridianWatchWidget (reader) only.

import Foundation

// MARK: - WatchWidgetStore

public enum WatchWidgetStore {

    /// Same App Group as the rest of the suite; on watchOS this container is shared
    /// between the watch app and its widget extension.
    public static let appGroupId = "group.com.example.meridian"

    static let fileName = "watch-widget-payload.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    /// Atomically persists the payload. No-op when the App Group is unavailable
    /// (widget then falls back to its placeholder state).
    public static func save(_ payload: WatchSyncPayload) {
        guard let url = fileURL else { return }
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    /// The last persisted payload, or `nil` when none exists or the schema is newer
    /// than this build understands (same version rule as `WatchSyncEncoding.decode`).
    public static func load() -> WatchSyncPayload? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let payload = try? decoder.decode(WatchSyncPayload.self, from: data),
              payload.version <= WatchSyncPayload.currentVersion else {
            return nil
        }
        return payload
    }
}
