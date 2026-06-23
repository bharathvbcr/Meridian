// PlaceIndex.swift
// Meridian — iOS 27+ / Swift 6
//
// Ported from app/src/main/java/com/example/core/time/PlaceIndex.kt
//
// Curated city / country / alias → IANA-zone index for the location search.
//
// The raw IANA id is a poor search key: a user typing "San Francisco", "Mumbai", "Beijing" or
// "Munich" finds nothing because those words never appear in `America/Los_Angeles`,
// `Asia/Kolkata`, `Asia/Shanghai` or `Europe/Berlin`. This table maps the names people actually
// type — major cities, countries, alternate spellings, and airport codes — onto the correct zone.
//
// Offline and privacy-friendly: a static table, no network. It complements the raw IANA-id search
// rather than replacing it, so obscure zones remain reachable by their id.

import Foundation

// MARK: - PlaceEntry

/// A single searchable place. `displayName` (city) and `country` are shown to the user; `aliases`
/// are extra search terms only (alternate spellings, airport codes, well-known nicknames).
public struct PlaceEntry: Identifiable, Hashable, Sendable {
    /// Stable identifier — equal to `tzId`.
    public let id: String
    /// IANA timezone identifier, e.g. `"America/New_York"`.
    public let tzId: String
    /// Human-readable city name, e.g. `"New York"`.
    public let displayName: String
    /// Country or territory name, e.g. `"United States"`.
    public let country: String
    /// Alternative search terms: airport codes (IATA), local spellings, nicknames.
    public let aliases: [String]

    public init(tzId: String, displayName: String, country: String, aliases: [String] = []) {
        self.id = tzId
        self.tzId = tzId
        self.displayName = displayName
        self.country = country
        self.aliases = aliases
    }
}

// MARK: - PlaceIndex

/// Searchable curated city index backed by a static dataset, with Android-parity ranking:
/// an exact term beats a prefix term beats a substring term, ties broken by city name.
public final class PlaceIndex: Sendable {

    /// Shared singleton.
    public static let shared = PlaceIndex()

    /// Lower-cased haystack per place, built once.
    private struct Indexed: Sendable {
        let place: PlaceEntry
        let haystacks: [String]
    }

    private let index: [Indexed]

    private init() {
        self.index = Self.places.map { p in
            var terms: [String] = [p.displayName, p.country, p.tzId]
            // zoneId last segment with underscores → spaces, e.g. "New_York" → "new york".
            let lastSegment = p.tzId.split(separator: "/").last.map(String.init) ?? p.tzId
            terms.append(lastSegment.replacingOccurrences(of: "_", with: " "))
            terms.append(contentsOf: p.aliases)
            return Indexed(place: p, haystacks: terms.map { $0.lowercased() })
        }
    }

    // MARK: Search

    /// Curated places matching `query`, best matches first. A term that *starts with* the query
    /// outranks one that merely *contains* it, so "san" surfaces "San Francisco" ahead of
    /// "Porto-Novo". Returns at most `limit` places.
    ///
    /// Matches Android `PlaceIndex.search`. An empty query returns `[]` (the iOS view layer must
    /// not show the whole table for an empty box).
    public func search(query: String, limit: Int = 10) -> [PlaceEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        var scored: [(place: PlaceEntry, rank: Int)] = []
        for indexed in index {
            let rank = Self.rankOf(haystacks: indexed.haystacks, query: q)
            if rank != Self.noMatch { scored.append((indexed.place, rank)) }
        }
        // Sort ascending by rank, then by city name for stability (matches Kotlin compareBy).
        scored.sort { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.place.displayName < rhs.place.displayName
        }
        return scored.prefix(limit).map(\.place)
    }

    /// Returns the curated entry for an exact IANA timezone id, or `nil`.
    public func entry(for tzId: String) -> PlaceEntry? {
        Self.places.first { $0.tzId == tzId }
    }

    /// Best match's `tzId`, or `nil`. Thin convenience over ``search(query:limit:)``.
    public func resolveTimezone(query: String) -> String? {
        search(query: query, limit: 1).first?.tzId
    }

    /// A high-confidence match for grounding and fast zone resolution — exact or prefix on city,
    /// country, or alias only. Unlike ``search(query:limit:)``, this ignores substring hits on the
    /// IANA id (so "york" does not match every `America/New_York` city) and is safe for single-token
    /// prompts. Mirrors Android `PlaceIndex.resolveConfident`.
    public func resolveConfident(query: String) -> PlaceEntry? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return nil }
        return Self.places.first { place in
            let city = place.displayName.lowercased()
            let country = place.country.lowercased()
            if city == q || city.hasPrefix(q) || country == q || country.hasPrefix(q) { return true }
            return place.aliases.contains { alias in
                let a = alias.lowercased()
                return a == q || a.hasPrefix(q)
            }
        }
    }

    // MARK: Ranking

    private static let noMatch = Int.max

    private static func rankOf(haystacks: [String], query q: String) -> Int {
        var best = noMatch
        for h in haystacks {
            let rank: Int
            if h == q {
                rank = 0
            } else if h.hasPrefix(q) {
                rank = 1
            } else if h.contains(q) {
                rank = 2
            } else {
                continue
            }
            if rank < best { best = rank }
            if best == 0 { break }
        }
        return best
    }

    // MARK: - Dataset

    /// Major world places keyed by what users type. Coordinates live in ``ZoneGeo``; this is purely
    /// a name → zone alias layer. Ordering is roughly by prominence within a zone so the most-typed
    /// city wins when several share an IANA id. Ported verbatim from `PlaceIndex.kt`'s `PLACES`.
    static let places: [PlaceEntry] = [
        // ---- North America: US Pacific ----
        PlaceEntry(tzId: "America/Los_Angeles", displayName: "San Francisco", country: "United States", aliases: ["sfo", "bay area", "silicon valley"]),
        PlaceEntry(tzId: "America/Los_Angeles", displayName: "Los Angeles", country: "United States", aliases: ["la", "lax"]),
        PlaceEntry(tzId: "America/Los_Angeles", displayName: "San Jose", country: "United States", aliases: ["sjc"]),
        PlaceEntry(tzId: "America/Los_Angeles", displayName: "San Diego", country: "United States", aliases: ["san"]),
        PlaceEntry(tzId: "America/Los_Angeles", displayName: "Seattle", country: "United States", aliases: ["sea"]),
        PlaceEntry(tzId: "America/Los_Angeles", displayName: "Portland", country: "United States", aliases: ["pdx"]),
        PlaceEntry(tzId: "America/Los_Angeles", displayName: "Las Vegas", country: "United States", aliases: ["las"]),
        PlaceEntry(tzId: "America/Los_Angeles", displayName: "Sacramento", country: "United States", aliases: ["smf"]),
        // ---- US Mountain / Arizona ----
        PlaceEntry(tzId: "America/Denver", displayName: "Denver", country: "United States", aliases: ["den"]),
        PlaceEntry(tzId: "America/Denver", displayName: "Salt Lake City", country: "United States", aliases: ["slc"]),
        PlaceEntry(tzId: "America/Denver", displayName: "Albuquerque", country: "United States", aliases: ["abq"]),
        PlaceEntry(tzId: "America/Phoenix", displayName: "Phoenix", country: "United States", aliases: ["phx", "arizona"]),
        // ---- US Central ----
        PlaceEntry(tzId: "America/Chicago", displayName: "Chicago", country: "United States", aliases: ["ord"]),
        PlaceEntry(tzId: "America/Chicago", displayName: "Dallas", country: "United States", aliases: ["dfw"]),
        PlaceEntry(tzId: "America/Chicago", displayName: "Houston", country: "United States", aliases: ["iah", "hou"]),
        PlaceEntry(tzId: "America/Chicago", displayName: "Austin", country: "United States", aliases: ["aus"]),
        PlaceEntry(tzId: "America/Chicago", displayName: "San Antonio", country: "United States", aliases: ["sat"]),
        PlaceEntry(tzId: "America/Chicago", displayName: "Minneapolis", country: "United States", aliases: ["msp"]),
        PlaceEntry(tzId: "America/Chicago", displayName: "New Orleans", country: "United States", aliases: ["msy"]),
        PlaceEntry(tzId: "America/Chicago", displayName: "Kansas City", country: "United States", aliases: ["mci"]),
        PlaceEntry(tzId: "America/Chicago", displayName: "Nashville", country: "United States", aliases: ["bna"]),
        // ---- US Eastern ----
        PlaceEntry(tzId: "America/New_York", displayName: "New York", country: "United States", aliases: ["nyc", "jfk", "manhattan", "lga"]),
        PlaceEntry(tzId: "America/New_York", displayName: "Washington", country: "United States", aliases: ["dc", "washington dc", "iad", "dca"]),
        PlaceEntry(tzId: "America/New_York", displayName: "Boston", country: "United States", aliases: ["bos"]),
        PlaceEntry(tzId: "America/New_York", displayName: "Philadelphia", country: "United States", aliases: ["phl", "philly"]),
        PlaceEntry(tzId: "America/New_York", displayName: "Atlanta", country: "United States", aliases: ["atl"]),
        PlaceEntry(tzId: "America/New_York", displayName: "Miami", country: "United States", aliases: ["mia"]),
        PlaceEntry(tzId: "America/New_York", displayName: "Orlando", country: "United States", aliases: ["mco"]),
        PlaceEntry(tzId: "America/Detroit", displayName: "Detroit", country: "United States", aliases: ["dtw"]),
        PlaceEntry(tzId: "America/New_York", displayName: "Pittsburgh", country: "United States", aliases: ["pit"]),
        PlaceEntry(tzId: "America/New_York", displayName: "Charlotte", country: "United States", aliases: ["clt"]),
        // ---- US Alaska / Hawaii ----
        PlaceEntry(tzId: "America/Anchorage", displayName: "Anchorage", country: "United States", aliases: ["anc", "alaska"]),
        PlaceEntry(tzId: "Pacific/Honolulu", displayName: "Honolulu", country: "United States", aliases: ["hnl", "hawaii"]),
        // ---- Canada ----
        PlaceEntry(tzId: "America/Toronto", displayName: "Toronto", country: "Canada", aliases: ["yyz"]),
        PlaceEntry(tzId: "America/Toronto", displayName: "Ottawa", country: "Canada", aliases: ["yow"]),
        PlaceEntry(tzId: "America/Toronto", displayName: "Montreal", country: "Canada", aliases: ["yul"]),
        PlaceEntry(tzId: "America/Vancouver", displayName: "Vancouver", country: "Canada", aliases: ["yvr"]),
        PlaceEntry(tzId: "America/Edmonton", displayName: "Calgary", country: "Canada", aliases: ["yyc"]),
        PlaceEntry(tzId: "America/Edmonton", displayName: "Edmonton", country: "Canada", aliases: ["yeg"]),
        PlaceEntry(tzId: "America/Winnipeg", displayName: "Winnipeg", country: "Canada", aliases: ["ywg"]),
        PlaceEntry(tzId: "America/Halifax", displayName: "Halifax", country: "Canada", aliases: ["yhz"]),
        // ---- Mexico / Central America / Caribbean ----
        PlaceEntry(tzId: "America/Mexico_City", displayName: "Mexico City", country: "Mexico", aliases: ["mex", "cdmx"]),
        PlaceEntry(tzId: "America/Mexico_City", displayName: "Guadalajara", country: "Mexico", aliases: ["gdl"]),
        PlaceEntry(tzId: "America/Monterrey", displayName: "Monterrey", country: "Mexico", aliases: ["mty"]),
        PlaceEntry(tzId: "America/Cancun", displayName: "Cancun", country: "Mexico", aliases: ["cun"]),
        PlaceEntry(tzId: "America/Tijuana", displayName: "Tijuana", country: "Mexico", aliases: ["tij"]),
        PlaceEntry(tzId: "America/Panama", displayName: "Panama City", country: "Panama", aliases: ["pty"]),
        PlaceEntry(tzId: "America/Costa_Rica", displayName: "San Jose", country: "Costa Rica", aliases: ["sjo"]),
        PlaceEntry(tzId: "America/Havana", displayName: "Havana", country: "Cuba", aliases: ["hav"]),
        PlaceEntry(tzId: "America/Santo_Domingo", displayName: "Santo Domingo", country: "Dominican Republic", aliases: ["sdq"]),
        PlaceEntry(tzId: "America/Puerto_Rico", displayName: "San Juan", country: "Puerto Rico", aliases: ["sju"]),
        // ---- South America ----
        PlaceEntry(tzId: "America/Sao_Paulo", displayName: "Sao Paulo", country: "Brazil", aliases: ["gru", "são paulo"]),
        PlaceEntry(tzId: "America/Sao_Paulo", displayName: "Rio de Janeiro", country: "Brazil", aliases: ["gig", "rio"]),
        PlaceEntry(tzId: "America/Sao_Paulo", displayName: "Brasilia", country: "Brazil", aliases: ["bsb", "brasília"]),
        PlaceEntry(tzId: "America/Argentina/Buenos_Aires", displayName: "Buenos Aires", country: "Argentina", aliases: ["eze"]),
        PlaceEntry(tzId: "America/Santiago", displayName: "Santiago", country: "Chile", aliases: ["scl"]),
        PlaceEntry(tzId: "America/Lima", displayName: "Lima", country: "Peru", aliases: ["lim"]),
        PlaceEntry(tzId: "America/Bogota", displayName: "Bogota", country: "Colombia", aliases: ["bog", "bogotá"]),
        PlaceEntry(tzId: "America/Bogota", displayName: "Medellin", country: "Colombia", aliases: ["mde", "medellín"]),
        PlaceEntry(tzId: "America/Caracas", displayName: "Caracas", country: "Venezuela", aliases: ["ccs"]),
        PlaceEntry(tzId: "America/Guayaquil", displayName: "Quito", country: "Ecuador", aliases: ["uio"]),
        PlaceEntry(tzId: "America/Montevideo", displayName: "Montevideo", country: "Uruguay", aliases: ["mvd"]),
        PlaceEntry(tzId: "America/La_Paz", displayName: "La Paz", country: "Bolivia", aliases: ["lpb"]),
        // ---- UK & Ireland ----
        PlaceEntry(tzId: "Europe/London", displayName: "London", country: "United Kingdom", aliases: ["lhr", "lon", "uk", "england", "britain"]),
        PlaceEntry(tzId: "Europe/London", displayName: "Manchester", country: "United Kingdom", aliases: ["man"]),
        PlaceEntry(tzId: "Europe/London", displayName: "Birmingham", country: "United Kingdom", aliases: ["bhx"]),
        PlaceEntry(tzId: "Europe/London", displayName: "Edinburgh", country: "United Kingdom", aliases: ["edi", "scotland"]),
        PlaceEntry(tzId: "Europe/London", displayName: "Glasgow", country: "United Kingdom", aliases: ["gla"]),
        PlaceEntry(tzId: "Europe/Dublin", displayName: "Dublin", country: "Ireland", aliases: ["dub"]),
        // ---- Western Europe ----
        PlaceEntry(tzId: "Europe/Paris", displayName: "Paris", country: "France", aliases: ["cdg", "france"]),
        PlaceEntry(tzId: "Europe/Paris", displayName: "Nice", country: "France", aliases: ["nce"]),
        PlaceEntry(tzId: "Europe/Paris", displayName: "Lyon", country: "France", aliases: ["lys"]),
        PlaceEntry(tzId: "Europe/Paris", displayName: "Marseille", country: "France", aliases: ["mrs"]),
        PlaceEntry(tzId: "Europe/Berlin", displayName: "Berlin", country: "Germany", aliases: ["ber", "germany"]),
        PlaceEntry(tzId: "Europe/Berlin", displayName: "Munich", country: "Germany", aliases: ["muc", "münchen"]),
        PlaceEntry(tzId: "Europe/Berlin", displayName: "Frankfurt", country: "Germany", aliases: ["fra"]),
        PlaceEntry(tzId: "Europe/Berlin", displayName: "Hamburg", country: "Germany", aliases: ["ham"]),
        PlaceEntry(tzId: "Europe/Berlin", displayName: "Cologne", country: "Germany", aliases: ["cgn", "köln"]),
        PlaceEntry(tzId: "Europe/Madrid", displayName: "Madrid", country: "Spain", aliases: ["mad", "spain"]),
        PlaceEntry(tzId: "Europe/Madrid", displayName: "Barcelona", country: "Spain", aliases: ["bcn"]),
        PlaceEntry(tzId: "Europe/Madrid", displayName: "Valencia", country: "Spain", aliases: ["vlc"]),
        PlaceEntry(tzId: "Europe/Madrid", displayName: "Seville", country: "Spain", aliases: ["svq", "sevilla"]),
        PlaceEntry(tzId: "Europe/Rome", displayName: "Rome", country: "Italy", aliases: ["fco", "roma", "italy"]),
        PlaceEntry(tzId: "Europe/Rome", displayName: "Milan", country: "Italy", aliases: ["mxp", "milano"]),
        PlaceEntry(tzId: "Europe/Rome", displayName: "Venice", country: "Italy", aliases: ["vce", "venezia"]),
        PlaceEntry(tzId: "Europe/Rome", displayName: "Naples", country: "Italy", aliases: ["nap", "napoli"]),
        PlaceEntry(tzId: "Europe/Rome", displayName: "Florence", country: "Italy", aliases: ["flr", "firenze"]),
        PlaceEntry(tzId: "Europe/Amsterdam", displayName: "Amsterdam", country: "Netherlands", aliases: ["ams", "holland", "netherlands"]),
        PlaceEntry(tzId: "Europe/Brussels", displayName: "Brussels", country: "Belgium", aliases: ["bru"]),
        PlaceEntry(tzId: "Europe/Lisbon", displayName: "Lisbon", country: "Portugal", aliases: ["lis", "lisboa", "portugal"]),
        PlaceEntry(tzId: "Europe/Lisbon", displayName: "Porto", country: "Portugal", aliases: ["opo"]),
        PlaceEntry(tzId: "Europe/Zurich", displayName: "Zurich", country: "Switzerland", aliases: ["zrh", "switzerland"]),
        PlaceEntry(tzId: "Europe/Zurich", displayName: "Geneva", country: "Switzerland", aliases: ["gva"]),
        PlaceEntry(tzId: "Europe/Vienna", displayName: "Vienna", country: "Austria", aliases: ["vie", "wien", "austria"]),
        PlaceEntry(tzId: "Europe/Luxembourg", displayName: "Luxembourg", country: "Luxembourg", aliases: ["lux"]),
        // ---- Nordics ----
        PlaceEntry(tzId: "Europe/Stockholm", displayName: "Stockholm", country: "Sweden", aliases: ["arn", "sweden"]),
        PlaceEntry(tzId: "Europe/Copenhagen", displayName: "Copenhagen", country: "Denmark", aliases: ["cph", "denmark"]),
        PlaceEntry(tzId: "Europe/Oslo", displayName: "Oslo", country: "Norway", aliases: ["osl", "norway"]),
        PlaceEntry(tzId: "Europe/Helsinki", displayName: "Helsinki", country: "Finland", aliases: ["hel", "finland"]),
        PlaceEntry(tzId: "Atlantic/Reykjavik", displayName: "Reykjavik", country: "Iceland", aliases: ["kef", "iceland"]),
        // ---- Central & Eastern Europe ----
        PlaceEntry(tzId: "Europe/Warsaw", displayName: "Warsaw", country: "Poland", aliases: ["waw", "poland"]),
        PlaceEntry(tzId: "Europe/Prague", displayName: "Prague", country: "Czechia", aliases: ["prg", "praha", "czech republic"]),
        PlaceEntry(tzId: "Europe/Budapest", displayName: "Budapest", country: "Hungary", aliases: ["bud", "hungary"]),
        PlaceEntry(tzId: "Europe/Bucharest", displayName: "Bucharest", country: "Romania", aliases: ["otp", "romania"]),
        PlaceEntry(tzId: "Europe/Athens", displayName: "Athens", country: "Greece", aliases: ["ath", "greece"]),
        PlaceEntry(tzId: "Europe/Sofia", displayName: "Sofia", country: "Bulgaria", aliases: ["sof", "bulgaria"]),
        PlaceEntry(tzId: "Europe/Belgrade", displayName: "Belgrade", country: "Serbia", aliases: ["beg", "serbia"]),
        PlaceEntry(tzId: "Europe/Zagreb", displayName: "Zagreb", country: "Croatia", aliases: ["zag", "croatia"]),
        PlaceEntry(tzId: "Europe/Kyiv", displayName: "Kyiv", country: "Ukraine", aliases: ["kbp", "kiev", "ukraine"]),
        PlaceEntry(tzId: "Europe/Moscow", displayName: "Moscow", country: "Russia", aliases: ["svo", "moskva", "russia"]),
        PlaceEntry(tzId: "Europe/Moscow", displayName: "Saint Petersburg", country: "Russia", aliases: ["led", "st petersburg"]),
        PlaceEntry(tzId: "Europe/Istanbul", displayName: "Istanbul", country: "Turkey", aliases: ["ist", "turkey", "türkiye"]),
        // ---- Middle East ----
        PlaceEntry(tzId: "Asia/Dubai", displayName: "Dubai", country: "United Arab Emirates", aliases: ["dxb", "uae"]),
        PlaceEntry(tzId: "Asia/Dubai", displayName: "Abu Dhabi", country: "United Arab Emirates", aliases: ["auh"]),
        PlaceEntry(tzId: "Asia/Riyadh", displayName: "Riyadh", country: "Saudi Arabia", aliases: ["ruh", "saudi arabia"]),
        PlaceEntry(tzId: "Asia/Riyadh", displayName: "Jeddah", country: "Saudi Arabia", aliases: ["jed"]),
        PlaceEntry(tzId: "Asia/Qatar", displayName: "Doha", country: "Qatar", aliases: ["doh", "qatar"]),
        PlaceEntry(tzId: "Asia/Kuwait", displayName: "Kuwait City", country: "Kuwait", aliases: ["kwi"]),
        PlaceEntry(tzId: "Asia/Jerusalem", displayName: "Tel Aviv", country: "Israel", aliases: ["tlv"]),
        PlaceEntry(tzId: "Asia/Jerusalem", displayName: "Jerusalem", country: "Israel", aliases: ["israel"]),
        PlaceEntry(tzId: "Asia/Beirut", displayName: "Beirut", country: "Lebanon", aliases: ["bey", "lebanon"]),
        PlaceEntry(tzId: "Asia/Amman", displayName: "Amman", country: "Jordan", aliases: ["amm", "jordan"]),
        PlaceEntry(tzId: "Asia/Baghdad", displayName: "Baghdad", country: "Iraq", aliases: ["bgw", "iraq"]),
        PlaceEntry(tzId: "Asia/Tehran", displayName: "Tehran", country: "Iran", aliases: ["ika", "iran"]),
        // ---- South Asia ----
        PlaceEntry(tzId: "Asia/Kolkata", displayName: "Mumbai", country: "India", aliases: ["bom", "bombay"]),
        PlaceEntry(tzId: "Asia/Kolkata", displayName: "Delhi", country: "India", aliases: ["del", "new delhi"]),
        PlaceEntry(tzId: "Asia/Kolkata", displayName: "Bengaluru", country: "India", aliases: ["blr", "bangalore"]),
        PlaceEntry(tzId: "Asia/Kolkata", displayName: "Hyderabad", country: "India", aliases: ["hyd"]),
        PlaceEntry(tzId: "Asia/Kolkata", displayName: "Chennai", country: "India", aliases: ["maa", "madras"]),
        PlaceEntry(tzId: "Asia/Kolkata", displayName: "Kolkata", country: "India", aliases: ["ccu", "calcutta"]),
        PlaceEntry(tzId: "Asia/Kolkata", displayName: "Pune", country: "India", aliases: ["pnq"]),
        PlaceEntry(tzId: "Asia/Kolkata", displayName: "Ahmedabad", country: "India", aliases: ["amd"]),
        PlaceEntry(tzId: "Asia/Karachi", displayName: "Karachi", country: "Pakistan", aliases: ["khi", "pakistan"]),
        PlaceEntry(tzId: "Asia/Karachi", displayName: "Lahore", country: "Pakistan", aliases: ["lhe"]),
        PlaceEntry(tzId: "Asia/Karachi", displayName: "Islamabad", country: "Pakistan", aliases: ["isb"]),
        PlaceEntry(tzId: "Asia/Dhaka", displayName: "Dhaka", country: "Bangladesh", aliases: ["dac", "bangladesh"]),
        PlaceEntry(tzId: "Asia/Colombo", displayName: "Colombo", country: "Sri Lanka", aliases: ["cmb", "sri lanka"]),
        PlaceEntry(tzId: "Asia/Kathmandu", displayName: "Kathmandu", country: "Nepal", aliases: ["ktm", "nepal"]),
        // ---- East Asia ----
        PlaceEntry(tzId: "Asia/Tokyo", displayName: "Tokyo", country: "Japan", aliases: ["hnd", "nrt", "japan"]),
        PlaceEntry(tzId: "Asia/Tokyo", displayName: "Osaka", country: "Japan", aliases: ["kix"]),
        PlaceEntry(tzId: "Asia/Tokyo", displayName: "Kyoto", country: "Japan"),
        PlaceEntry(tzId: "Asia/Tokyo", displayName: "Nagoya", country: "Japan", aliases: ["ngo"]),
        PlaceEntry(tzId: "Asia/Seoul", displayName: "Seoul", country: "South Korea", aliases: ["icn", "south korea", "korea"]),
        PlaceEntry(tzId: "Asia/Seoul", displayName: "Busan", country: "South Korea", aliases: ["pus"]),
        PlaceEntry(tzId: "Asia/Shanghai", displayName: "Beijing", country: "China", aliases: ["pek", "peking", "china"]),
        PlaceEntry(tzId: "Asia/Shanghai", displayName: "Shanghai", country: "China", aliases: ["pvg"]),
        PlaceEntry(tzId: "Asia/Shanghai", displayName: "Shenzhen", country: "China", aliases: ["szx"]),
        PlaceEntry(tzId: "Asia/Shanghai", displayName: "Guangzhou", country: "China", aliases: ["can", "canton"]),
        PlaceEntry(tzId: "Asia/Hong_Kong", displayName: "Hong Kong", country: "Hong Kong", aliases: ["hkg"]),
        PlaceEntry(tzId: "Asia/Taipei", displayName: "Taipei", country: "Taiwan", aliases: ["tpe", "taiwan"]),
        // ---- Southeast Asia ----
        PlaceEntry(tzId: "Asia/Singapore", displayName: "Singapore", country: "Singapore", aliases: ["sin"]),
        PlaceEntry(tzId: "Asia/Bangkok", displayName: "Bangkok", country: "Thailand", aliases: ["bkk", "thailand"]),
        PlaceEntry(tzId: "Asia/Jakarta", displayName: "Jakarta", country: "Indonesia", aliases: ["cgk", "indonesia"]),
        PlaceEntry(tzId: "Asia/Makassar", displayName: "Bali", country: "Indonesia", aliases: ["dps", "denpasar"]),
        PlaceEntry(tzId: "Asia/Kuala_Lumpur", displayName: "Kuala Lumpur", country: "Malaysia", aliases: ["kul", "malaysia"]),
        PlaceEntry(tzId: "Asia/Manila", displayName: "Manila", country: "Philippines", aliases: ["mnl", "philippines"]),
        PlaceEntry(tzId: "Asia/Ho_Chi_Minh", displayName: "Ho Chi Minh City", country: "Vietnam", aliases: ["sgn", "saigon", "vietnam"]),
        PlaceEntry(tzId: "Asia/Bangkok", displayName: "Hanoi", country: "Vietnam", aliases: ["han"]),
        PlaceEntry(tzId: "Asia/Phnom_Penh", displayName: "Phnom Penh", country: "Cambodia", aliases: ["pnh", "cambodia"]),
        PlaceEntry(tzId: "Asia/Yangon", displayName: "Yangon", country: "Myanmar", aliases: ["rgn", "rangoon", "myanmar"]),
        // ---- Central Asia ----
        PlaceEntry(tzId: "Asia/Almaty", displayName: "Almaty", country: "Kazakhstan", aliases: ["ala", "kazakhstan"]),
        PlaceEntry(tzId: "Asia/Tashkent", displayName: "Tashkent", country: "Uzbekistan", aliases: ["tas", "uzbekistan"]),
        PlaceEntry(tzId: "Asia/Baku", displayName: "Baku", country: "Azerbaijan", aliases: ["gyd", "azerbaijan"]),
        PlaceEntry(tzId: "Asia/Tbilisi", displayName: "Tbilisi", country: "Georgia", aliases: ["tbs", "georgia"]),
        PlaceEntry(tzId: "Asia/Yerevan", displayName: "Yerevan", country: "Armenia", aliases: ["evn", "armenia"]),
        // ---- Africa ----
        PlaceEntry(tzId: "Africa/Cairo", displayName: "Cairo", country: "Egypt", aliases: ["cai", "egypt"]),
        PlaceEntry(tzId: "Africa/Lagos", displayName: "Lagos", country: "Nigeria", aliases: ["los", "nigeria"]),
        PlaceEntry(tzId: "Africa/Lagos", displayName: "Abuja", country: "Nigeria", aliases: ["abv"]),
        PlaceEntry(tzId: "Africa/Nairobi", displayName: "Nairobi", country: "Kenya", aliases: ["nbo", "kenya"]),
        PlaceEntry(tzId: "Africa/Johannesburg", displayName: "Johannesburg", country: "South Africa", aliases: ["jnb", "joburg", "south africa"]),
        PlaceEntry(tzId: "Africa/Johannesburg", displayName: "Cape Town", country: "South Africa", aliases: ["cpt"]),
        PlaceEntry(tzId: "Africa/Johannesburg", displayName: "Pretoria", country: "South Africa"),
        PlaceEntry(tzId: "Africa/Johannesburg", displayName: "Durban", country: "South Africa", aliases: ["dur"]),
        PlaceEntry(tzId: "Africa/Casablanca", displayName: "Casablanca", country: "Morocco", aliases: ["cmn", "morocco"]),
        PlaceEntry(tzId: "Africa/Accra", displayName: "Accra", country: "Ghana", aliases: ["acc", "ghana"]),
        PlaceEntry(tzId: "Africa/Addis_Ababa", displayName: "Addis Ababa", country: "Ethiopia", aliases: ["add", "ethiopia"]),
        PlaceEntry(tzId: "Africa/Dar_es_Salaam", displayName: "Dar es Salaam", country: "Tanzania", aliases: ["dar", "tanzania"]),
        PlaceEntry(tzId: "Africa/Algiers", displayName: "Algiers", country: "Algeria", aliases: ["alg", "algeria"]),
        PlaceEntry(tzId: "Africa/Tunis", displayName: "Tunis", country: "Tunisia", aliases: ["tun", "tunisia"]),
        PlaceEntry(tzId: "Africa/Kinshasa", displayName: "Kinshasa", country: "DR Congo", aliases: ["fih"]),
        // ---- Oceania ----
        PlaceEntry(tzId: "Australia/Sydney", displayName: "Sydney", country: "Australia", aliases: ["syd", "australia"]),
        PlaceEntry(tzId: "Australia/Melbourne", displayName: "Melbourne", country: "Australia", aliases: ["mel"]),
        PlaceEntry(tzId: "Australia/Brisbane", displayName: "Brisbane", country: "Australia", aliases: ["bne"]),
        PlaceEntry(tzId: "Australia/Perth", displayName: "Perth", country: "Australia", aliases: ["per"]),
        PlaceEntry(tzId: "Australia/Adelaide", displayName: "Adelaide", country: "Australia", aliases: ["adl"]),
        PlaceEntry(tzId: "Australia/Sydney", displayName: "Canberra", country: "Australia", aliases: ["cbr"]),
        PlaceEntry(tzId: "Pacific/Auckland", displayName: "Auckland", country: "New Zealand", aliases: ["akl", "new zealand"]),
        PlaceEntry(tzId: "Pacific/Auckland", displayName: "Wellington", country: "New Zealand", aliases: ["wlg"]),
        PlaceEntry(tzId: "Pacific/Fiji", displayName: "Suva", country: "Fiji", aliases: ["suv", "fiji"]),
        PlaceEntry(tzId: "Pacific/Guadalcanal", displayName: "Honiara", country: "Solomon Islands"),
        PlaceEntry(tzId: "Pacific/Port_Moresby", displayName: "Port Moresby", country: "Papua New Guinea", aliases: ["pom"]),
    ]
}
