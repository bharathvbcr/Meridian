package com.example.core.time

import java.util.Locale

/**
 * Curated city / country / alias → IANA-zone index for the location search (§5.1).
 *
 * The raw IANA id is a poor search key: a user typing "San Francisco", "Mumbai", "Beijing" or
 * "Munich" finds nothing because those words never appear in `America/Los_Angeles`,
 * `Asia/Kolkata`, `Asia/Shanghai` or `Europe/Berlin`. This table maps the names people actually
 * type — major cities, countries, alternate spellings, and airport codes — onto the correct zone.
 *
 * Offline and privacy-friendly: it's a static table, no network. It complements the raw IANA-id
 * search rather than replacing it, so obscure zones remain reachable by their id.
 */
object PlaceIndex {

    /**
     * A searchable place. [city] and [country] are shown to the user; [aliases] are extra search
     * terms only (alternate spellings, airport codes, well-known nicknames).
     */
    data class Place(
        val city: String,
        val country: String,
        val zoneId: String,
        val aliases: List<String> = emptyList(),
    )

    /**
     * Major world places keyed by what users type. Coordinates live in [ZoneCoordinates]; this is
     * purely a name → zone alias layer. Ordering is roughly by prominence within a zone so the
     * most-typed city wins when several share an IANA id.
     */
    val PLACES: List<Place> = listOf(
        // ---- North America: US Pacific ----
        Place("San Francisco", "United States", "America/Los_Angeles", listOf("sfo", "bay area", "silicon valley")),
        Place("Los Angeles", "United States", "America/Los_Angeles", listOf("la", "lax")),
        Place("San Jose", "United States", "America/Los_Angeles", listOf("sjc")),
        Place("San Diego", "United States", "America/Los_Angeles", listOf("san")),
        Place("Seattle", "United States", "America/Los_Angeles", listOf("sea")),
        Place("Portland", "United States", "America/Los_Angeles", listOf("pdx")),
        Place("Las Vegas", "United States", "America/Los_Angeles", listOf("las")),
        Place("Sacramento", "United States", "America/Los_Angeles", listOf("smf")),
        // ---- US Mountain / Arizona ----
        Place("Denver", "United States", "America/Denver", listOf("den")),
        Place("Salt Lake City", "United States", "America/Denver", listOf("slc")),
        Place("Albuquerque", "United States", "America/Denver", listOf("abq")),
        Place("Phoenix", "United States", "America/Phoenix", listOf("phx", "arizona")),
        // ---- US Central ----
        Place("Chicago", "United States", "America/Chicago", listOf("ord")),
        Place("Dallas", "United States", "America/Chicago", listOf("dfw")),
        Place("Houston", "United States", "America/Chicago", listOf("iah", "hou")),
        Place("Austin", "United States", "America/Chicago", listOf("aus")),
        Place("San Antonio", "United States", "America/Chicago", listOf("sat")),
        Place("Minneapolis", "United States", "America/Chicago", listOf("msp")),
        Place("New Orleans", "United States", "America/Chicago", listOf("msy")),
        Place("Kansas City", "United States", "America/Chicago", listOf("mci")),
        Place("Nashville", "United States", "America/Chicago", listOf("bna")),
        // ---- US Eastern ----
        Place("New York", "United States", "America/New_York", listOf("nyc", "jfk", "manhattan", "lga")),
        Place("Washington", "United States", "America/New_York", listOf("dc", "washington dc", "iad", "dca")),
        Place("Boston", "United States", "America/New_York", listOf("bos")),
        Place("Philadelphia", "United States", "America/New_York", listOf("phl", "philly")),
        Place("Atlanta", "United States", "America/New_York", listOf("atl")),
        Place("Miami", "United States", "America/New_York", listOf("mia")),
        Place("Orlando", "United States", "America/New_York", listOf("mco")),
        Place("Detroit", "United States", "America/Detroit", listOf("dtw")),
        Place("Pittsburgh", "United States", "America/New_York", listOf("pit")),
        Place("Charlotte", "United States", "America/New_York", listOf("clt")),
        // ---- US Alaska / Hawaii ----
        Place("Anchorage", "United States", "America/Anchorage", listOf("anc", "alaska")),
        Place("Honolulu", "United States", "Pacific/Honolulu", listOf("hnl", "hawaii")),
        // ---- Canada ----
        Place("Toronto", "Canada", "America/Toronto", listOf("yyz")),
        Place("Ottawa", "Canada", "America/Toronto", listOf("yow")),
        Place("Montreal", "Canada", "America/Toronto", listOf("yul")),
        Place("Vancouver", "Canada", "America/Vancouver", listOf("yvr")),
        Place("Calgary", "Canada", "America/Edmonton", listOf("yyc")),
        Place("Edmonton", "Canada", "America/Edmonton", listOf("yeg")),
        Place("Winnipeg", "Canada", "America/Winnipeg", listOf("ywg")),
        Place("Halifax", "Canada", "America/Halifax", listOf("yhz")),
        // ---- Mexico / Central America / Caribbean ----
        Place("Mexico City", "Mexico", "America/Mexico_City", listOf("mex", "cdmx")),
        Place("Guadalajara", "Mexico", "America/Mexico_City", listOf("gdl")),
        Place("Monterrey", "Mexico", "America/Monterrey", listOf("mty")),
        Place("Cancun", "Mexico", "America/Cancun", listOf("cun")),
        Place("Tijuana", "Mexico", "America/Tijuana", listOf("tij")),
        Place("Panama City", "Panama", "America/Panama", listOf("pty")),
        Place("San Jose", "Costa Rica", "America/Costa_Rica", listOf("sjo")),
        Place("Havana", "Cuba", "America/Havana", listOf("hav")),
        Place("Santo Domingo", "Dominican Republic", "America/Santo_Domingo", listOf("sdq")),
        Place("San Juan", "Puerto Rico", "America/Puerto_Rico", listOf("sju")),
        // ---- South America ----
        Place("Sao Paulo", "Brazil", "America/Sao_Paulo", listOf("gru", "são paulo")),
        Place("Rio de Janeiro", "Brazil", "America/Sao_Paulo", listOf("gig", "rio")),
        Place("Brasilia", "Brazil", "America/Sao_Paulo", listOf("bsb", "brasília")),
        Place("Buenos Aires", "Argentina", "America/Argentina/Buenos_Aires", listOf("eze")),
        Place("Santiago", "Chile", "America/Santiago", listOf("scl")),
        Place("Lima", "Peru", "America/Lima", listOf("lim")),
        Place("Bogota", "Colombia", "America/Bogota", listOf("bog", "bogotá")),
        Place("Medellin", "Colombia", "America/Bogota", listOf("mde", "medellín")),
        Place("Caracas", "Venezuela", "America/Caracas", listOf("ccs")),
        Place("Quito", "Ecuador", "America/Guayaquil", listOf("uio")),
        Place("Montevideo", "Uruguay", "America/Montevideo", listOf("mvd")),
        Place("La Paz", "Bolivia", "America/La_Paz", listOf("lpb")),
        // ---- UK & Ireland ----
        Place("London", "United Kingdom", "Europe/London", listOf("lhr", "lon", "uk", "england", "britain")),
        Place("Manchester", "United Kingdom", "Europe/London", listOf("man")),
        Place("Birmingham", "United Kingdom", "Europe/London", listOf("bhx")),
        Place("Edinburgh", "United Kingdom", "Europe/London", listOf("edi", "scotland")),
        Place("Glasgow", "United Kingdom", "Europe/London", listOf("gla")),
        Place("Dublin", "Ireland", "Europe/Dublin", listOf("dub")),
        // ---- Western Europe ----
        Place("Paris", "France", "Europe/Paris", listOf("cdg", "france")),
        Place("Nice", "France", "Europe/Paris", listOf("nce")),
        Place("Lyon", "France", "Europe/Paris", listOf("lys")),
        Place("Marseille", "France", "Europe/Paris", listOf("mrs")),
        Place("Berlin", "Germany", "Europe/Berlin", listOf("ber", "germany")),
        Place("Munich", "Germany", "Europe/Berlin", listOf("muc", "münchen")),
        Place("Frankfurt", "Germany", "Europe/Berlin", listOf("fra")),
        Place("Hamburg", "Germany", "Europe/Berlin", listOf("ham")),
        Place("Cologne", "Germany", "Europe/Berlin", listOf("cgn", "köln")),
        Place("Madrid", "Spain", "Europe/Madrid", listOf("mad", "spain")),
        Place("Barcelona", "Spain", "Europe/Madrid", listOf("bcn")),
        Place("Valencia", "Spain", "Europe/Madrid", listOf("vlc")),
        Place("Seville", "Spain", "Europe/Madrid", listOf("svq", "sevilla")),
        Place("Rome", "Italy", "Europe/Rome", listOf("fco", "roma", "italy")),
        Place("Milan", "Italy", "Europe/Rome", listOf("mxp", "milano")),
        Place("Venice", "Italy", "Europe/Rome", listOf("vce", "venezia")),
        Place("Naples", "Italy", "Europe/Rome", listOf("nap", "napoli")),
        Place("Florence", "Italy", "Europe/Rome", listOf("flr", "firenze")),
        Place("Amsterdam", "Netherlands", "Europe/Amsterdam", listOf("ams", "holland", "netherlands")),
        Place("Brussels", "Belgium", "Europe/Brussels", listOf("bru")),
        Place("Lisbon", "Portugal", "Europe/Lisbon", listOf("lis", "lisboa", "portugal")),
        Place("Porto", "Portugal", "Europe/Lisbon", listOf("opo")),
        Place("Zurich", "Switzerland", "Europe/Zurich", listOf("zrh", "switzerland")),
        Place("Geneva", "Switzerland", "Europe/Zurich", listOf("gva")),
        Place("Vienna", "Austria", "Europe/Vienna", listOf("vie", "wien", "austria")),
        Place("Luxembourg", "Luxembourg", "Europe/Luxembourg", listOf("lux")),
        // ---- Nordics ----
        Place("Stockholm", "Sweden", "Europe/Stockholm", listOf("arn", "sweden")),
        Place("Copenhagen", "Denmark", "Europe/Copenhagen", listOf("cph", "denmark")),
        Place("Oslo", "Norway", "Europe/Oslo", listOf("osl", "norway")),
        Place("Helsinki", "Finland", "Europe/Helsinki", listOf("hel", "finland")),
        Place("Reykjavik", "Iceland", "Atlantic/Reykjavik", listOf("kef", "iceland")),
        // ---- Central & Eastern Europe ----
        Place("Warsaw", "Poland", "Europe/Warsaw", listOf("waw", "poland")),
        Place("Prague", "Czechia", "Europe/Prague", listOf("prg", "praha", "czech republic")),
        Place("Budapest", "Hungary", "Europe/Budapest", listOf("bud", "hungary")),
        Place("Bucharest", "Romania", "Europe/Bucharest", listOf("otp", "romania")),
        Place("Athens", "Greece", "Europe/Athens", listOf("ath", "greece")),
        Place("Sofia", "Bulgaria", "Europe/Sofia", listOf("sof", "bulgaria")),
        Place("Belgrade", "Serbia", "Europe/Belgrade", listOf("beg", "serbia")),
        Place("Zagreb", "Croatia", "Europe/Zagreb", listOf("zag", "croatia")),
        Place("Kyiv", "Ukraine", "Europe/Kyiv", listOf("kbp", "kiev", "ukraine")),
        Place("Moscow", "Russia", "Europe/Moscow", listOf("svo", "moskva", "russia")),
        Place("Saint Petersburg", "Russia", "Europe/Moscow", listOf("led", "st petersburg")),
        Place("Istanbul", "Turkey", "Europe/Istanbul", listOf("ist", "turkey", "türkiye")),
        // ---- Middle East ----
        Place("Dubai", "United Arab Emirates", "Asia/Dubai", listOf("dxb", "uae")),
        Place("Abu Dhabi", "United Arab Emirates", "Asia/Dubai", listOf("auh")),
        Place("Riyadh", "Saudi Arabia", "Asia/Riyadh", listOf("ruh", "saudi arabia")),
        Place("Jeddah", "Saudi Arabia", "Asia/Riyadh", listOf("jed")),
        Place("Doha", "Qatar", "Asia/Qatar", listOf("doh", "qatar")),
        Place("Kuwait City", "Kuwait", "Asia/Kuwait", listOf("kwi")),
        Place("Tel Aviv", "Israel", "Asia/Jerusalem", listOf("tlv")),
        Place("Jerusalem", "Israel", "Asia/Jerusalem", listOf("israel")),
        Place("Beirut", "Lebanon", "Asia/Beirut", listOf("bey", "lebanon")),
        Place("Amman", "Jordan", "Asia/Amman", listOf("amm", "jordan")),
        Place("Baghdad", "Iraq", "Asia/Baghdad", listOf("bgw", "iraq")),
        Place("Tehran", "Iran", "Asia/Tehran", listOf("ika", "iran")),
        // ---- South Asia ----
        Place("Mumbai", "India", "Asia/Kolkata", listOf("bom", "bombay")),
        Place("Delhi", "India", "Asia/Kolkata", listOf("del", "new delhi")),
        Place("Bengaluru", "India", "Asia/Kolkata", listOf("blr", "bangalore")),
        Place("Hyderabad", "India", "Asia/Kolkata", listOf("hyd")),
        Place("Chennai", "India", "Asia/Kolkata", listOf("maa", "madras")),
        Place("Kolkata", "India", "Asia/Kolkata", listOf("ccu", "calcutta")),
        Place("Pune", "India", "Asia/Kolkata", listOf("pnq")),
        Place("Ahmedabad", "India", "Asia/Kolkata", listOf("amd")),
        Place("Karachi", "Pakistan", "Asia/Karachi", listOf("khi", "pakistan")),
        Place("Lahore", "Pakistan", "Asia/Karachi", listOf("lhe")),
        Place("Islamabad", "Pakistan", "Asia/Karachi", listOf("isb")),
        Place("Dhaka", "Bangladesh", "Asia/Dhaka", listOf("dac", "bangladesh")),
        Place("Colombo", "Sri Lanka", "Asia/Colombo", listOf("cmb", "sri lanka")),
        Place("Kathmandu", "Nepal", "Asia/Kathmandu", listOf("ktm", "nepal")),
        // ---- East Asia ----
        Place("Tokyo", "Japan", "Asia/Tokyo", listOf("hnd", "nrt", "japan")),
        Place("Osaka", "Japan", "Asia/Tokyo", listOf("kix")),
        Place("Kyoto", "Japan", "Asia/Tokyo"),
        Place("Nagoya", "Japan", "Asia/Tokyo", listOf("ngo")),
        Place("Seoul", "South Korea", "Asia/Seoul", listOf("icn", "south korea", "korea")),
        Place("Busan", "South Korea", "Asia/Seoul", listOf("pus")),
        Place("Beijing", "China", "Asia/Shanghai", listOf("pek", "peking", "china")),
        Place("Shanghai", "China", "Asia/Shanghai", listOf("pvg")),
        Place("Shenzhen", "China", "Asia/Shanghai", listOf("szx")),
        Place("Guangzhou", "China", "Asia/Shanghai", listOf("can", "canton")),
        Place("Hong Kong", "Hong Kong", "Asia/Hong_Kong", listOf("hkg")),
        Place("Taipei", "Taiwan", "Asia/Taipei", listOf("tpe", "taiwan")),
        // ---- Southeast Asia ----
        Place("Singapore", "Singapore", "Asia/Singapore", listOf("sin")),
        Place("Bangkok", "Thailand", "Asia/Bangkok", listOf("bkk", "thailand")),
        Place("Jakarta", "Indonesia", "Asia/Jakarta", listOf("cgk", "indonesia")),
        Place("Bali", "Indonesia", "Asia/Makassar", listOf("dps", "denpasar")),
        Place("Kuala Lumpur", "Malaysia", "Asia/Kuala_Lumpur", listOf("kul", "malaysia")),
        Place("Manila", "Philippines", "Asia/Manila", listOf("mnl", "philippines")),
        Place("Ho Chi Minh City", "Vietnam", "Asia/Ho_Chi_Minh", listOf("sgn", "saigon", "vietnam")),
        Place("Hanoi", "Vietnam", "Asia/Bangkok", listOf("han")),
        Place("Phnom Penh", "Cambodia", "Asia/Phnom_Penh", listOf("pnh", "cambodia")),
        Place("Yangon", "Myanmar", "Asia/Yangon", listOf("rgn", "rangoon", "myanmar")),
        // ---- Central Asia ----
        Place("Almaty", "Kazakhstan", "Asia/Almaty", listOf("ala", "kazakhstan")),
        Place("Tashkent", "Uzbekistan", "Asia/Tashkent", listOf("tas", "uzbekistan")),
        Place("Baku", "Azerbaijan", "Asia/Baku", listOf("gyd", "azerbaijan")),
        Place("Tbilisi", "Georgia", "Asia/Tbilisi", listOf("tbs", "georgia")),
        Place("Yerevan", "Armenia", "Asia/Yerevan", listOf("evn", "armenia")),
        // ---- Africa ----
        Place("Cairo", "Egypt", "Africa/Cairo", listOf("cai", "egypt")),
        Place("Lagos", "Nigeria", "Africa/Lagos", listOf("los", "nigeria")),
        Place("Abuja", "Nigeria", "Africa/Lagos", listOf("abv")),
        Place("Nairobi", "Kenya", "Africa/Nairobi", listOf("nbo", "kenya")),
        Place("Johannesburg", "South Africa", "Africa/Johannesburg", listOf("jnb", "joburg", "south africa")),
        Place("Cape Town", "South Africa", "Africa/Johannesburg", listOf("cpt")),
        Place("Pretoria", "South Africa", "Africa/Johannesburg"),
        Place("Durban", "South Africa", "Africa/Johannesburg", listOf("dur")),
        Place("Casablanca", "Morocco", "Africa/Casablanca", listOf("cmn", "morocco")),
        Place("Accra", "Ghana", "Africa/Accra", listOf("acc", "ghana")),
        Place("Addis Ababa", "Ethiopia", "Africa/Addis_Ababa", listOf("add", "ethiopia")),
        Place("Dar es Salaam", "Tanzania", "Africa/Dar_es_Salaam", listOf("dar", "tanzania")),
        Place("Algiers", "Algeria", "Africa/Algiers", listOf("alg", "algeria")),
        Place("Tunis", "Tunisia", "Africa/Tunis", listOf("tun", "tunisia")),
        Place("Kinshasa", "DR Congo", "Africa/Kinshasa", listOf("fih")),
        // ---- Oceania ----
        Place("Sydney", "Australia", "Australia/Sydney", listOf("syd", "australia")),
        Place("Melbourne", "Australia", "Australia/Melbourne", listOf("mel")),
        Place("Brisbane", "Australia", "Australia/Brisbane", listOf("bne")),
        Place("Perth", "Australia", "Australia/Perth", listOf("per")),
        Place("Adelaide", "Australia", "Australia/Adelaide", listOf("adl")),
        Place("Canberra", "Australia", "Australia/Sydney", listOf("cbr")),
        Place("Auckland", "New Zealand", "Pacific/Auckland", listOf("akl", "new zealand")),
        Place("Wellington", "New Zealand", "Pacific/Auckland", listOf("wlg")),
        Place("Suva", "Fiji", "Pacific/Fiji", listOf("suv", "fiji")),
        Place("Honiara", "Solomon Islands", "Pacific/Guadalcanal"),
        Place("Port Moresby", "Papua New Guinea", "Pacific/Port_Moresby", listOf("pom")),
    )

    /** Lower-cased haystack per place, built once. */
    private data class Indexed(val place: Place, val haystacks: List<String>)

    private val INDEX: List<Indexed> = PLACES.map { p ->
        val terms = buildList {
            add(p.city)
            add(p.country)
            add(p.zoneId)
            add(p.zoneId.substringAfterLast('/').replace('_', ' '))
            addAll(p.aliases)
        }.map { it.lowercase(Locale.ROOT) }
        Indexed(p, terms)
    }

    /**
     * Curated places matching [query], best matches first. A term that *starts with* the query
     * outranks one that merely contains it, so "san" surfaces "San Francisco" ahead of
     * "Porto-Novo". Returns at most [limit] places.
     */
    fun search(query: String, limit: Int = 10): List<Place> {
        val q = query.trim().lowercase(Locale.ROOT)
        if (q.isEmpty()) return emptyList()
        return INDEX.asSequence()
            .mapNotNull { indexed ->
                val rank = rankOf(indexed.haystacks, q)
                if (rank == NO_MATCH) null else indexed.place to rank
            }
            .sortedWith(compareBy({ it.second }, { it.first.city }))
            .map { it.first }
            .take(limit)
            .toList()
    }

    /**
     * A high-confidence match for grounding and fast zone resolution — exact or prefix on city,
     * country, or alias only. Unlike [search], this ignores substring hits on the IANA id (so
     * "york" does not match every `America/New_York` city) and is safe for single-token prompts.
     */
    fun resolveConfident(query: String): Place? {
        val q = query.trim().lowercase(Locale.ROOT)
        if (q.isEmpty()) return null
        return PLACES.firstOrNull { place ->
            val city = place.city.lowercase(Locale.ROOT)
            val country = place.country.lowercase(Locale.ROOT)
            city == q || city.startsWith(q) || country == q || country.startsWith(q) ||
                place.aliases.any { alias ->
                    val a = alias.lowercase(Locale.ROOT)
                    a == q || a.startsWith(q)
                }
        }
    }

    private const val NO_MATCH = Int.MAX_VALUE

    private fun rankOf(haystacks: List<String>, q: String): Int {
        var best = NO_MATCH
        for (h in haystacks) {
            val rank = when {
                h == q -> 0
                h.startsWith(q) -> 1
                h.contains(q) -> 2
                else -> continue
            }
            if (rank < best) best = rank
            if (best == 0) break
        }
        return best
    }
}
