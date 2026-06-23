// SolarMath.swift
// Meridian — iOS 27 / Swift 6
//
// Deterministic solar geometry used by the day/night terminator and sun times.
// Pure functions of a `Date` — no `Date()` calls — so every value is testable.
//
// Two layers live here:
//  1. A high-precision NOAA / Meeus model (sunDeclination, equationOfTime, …) used for
//     sunrise/sunset wall-clock times and the solar-elevation display.
//  2. A low-precision subsolar-point model (≈ arc-minute accuracy) ported verbatim from the
//     Android source (`SolarMath.kt`), used by the terminator and the `isDaylight` /
//     `cosSolarZenith` checks so the terminator matches Android pixel-for-pixel.

import Foundation

// MARK: - GeoPoint

/// A point on Earth in degrees; longitude is east-positive.
public struct GeoPoint: Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: - SolarInfo

/// Encapsulates the result of a solar calculation for a given location and time.
public struct SolarInfo: Sendable {
    /// Local sunrise time; nil when the sun does not rise (polar night or midnight sun).
    public let sunrise: Date?
    /// Local sunset time; nil when the sun does not set.
    public let sunset: Date?
    /// Whether the sun is above the horizon at the requested instant.
    public let isDaytime: Bool
    /// Solar elevation angle in degrees (negative = below horizon).
    public let solarElevationAngle: Double
    /// `true` when the sun never sets on this date at this latitude (midnight sun).
    public let polarDay: Bool
    /// `true` when the sun never rises on this date at this latitude (polar night).
    public let polarNight: Bool

    public init(
        sunrise: Date?,
        sunset: Date?,
        isDaytime: Bool,
        solarElevationAngle: Double,
        polarDay: Bool = false,
        polarNight: Bool = false
    ) {
        self.sunrise = sunrise
        self.sunset = sunset
        self.isDaytime = isDaytime
        self.solarElevationAngle = solarElevationAngle
        self.polarDay = polarDay
        self.polarNight = polarNight
    }
}

// MARK: - SolarMath

/// Pure namespace for solar-position calculations.
///
/// All angles are in degrees unless a helper converts to/from radians explicitly.
public enum SolarMath {

    // MARK: Constants

    private static let j2000 = 2451545.0
    private static let deg = Double.pi / 180.0

    // MARK: Private helpers

    private static func toRad(_ deg: Double) -> Double { deg * .pi / 180.0 }
    private static func toDeg(_ rad: Double) -> Double { rad * 180.0 / .pi }

    /// Julian Day Number for a given Date.
    private static func julianDay(for date: Date) -> Double {
        // Unix epoch (1970-Jan-01 00:00 UTC) = JD 2440587.5
        date.timeIntervalSince1970 / 86400.0 + 2440587.5
    }

    /// Julian centuries from J2000.0.
    private static func julianCentury(_ jd: Double) -> Double {
        (jd - j2000) / 36525.0
    }

    /// Normalises an angle in degrees into the half-open range (-180, 180].
    private static func normalizeDegrees180(_ deg: Double) -> Double {
        var v = deg.truncatingRemainder(dividingBy: 360.0)
        if v > 180.0 { v -= 360.0 }
        if v < -180.0 { v += 360.0 }
        return v
    }

    // MARK: High-precision NOAA / Meeus model

    /// Geometric mean longitude of the Sun (degrees, corrected for aberration).
    private static func geomMeanLongSun(_ t: Double) -> Double {
        var l0 = 280.46646 + t * (36000.76983 + t * 0.0003032)
        l0 = l0.truncatingRemainder(dividingBy: 360.0)
        if l0 < 0 { l0 += 360.0 }
        return l0
    }

    /// Geometric mean anomaly of the Sun (degrees).
    private static func geomMeanAnomalySun(_ t: Double) -> Double {
        357.52911 + t * (35999.05029 - 0.0001537 * t)
    }

    /// Equation of centre for the Sun (degrees).
    private static func equationOfCentre(_ t: Double, meanAnomaly m: Double) -> Double {
        let mRad = toRad(m)
        return sin(mRad) * (1.914602 - t * (0.004817 + 0.000014 * t))
             + sin(2 * mRad) * (0.019993 - 0.000101 * t)
             + sin(3 * mRad) * 0.000289
    }

    /// Sun's true ecliptic longitude (degrees).
    private static func sunTrueLong(_ t: Double) -> Double {
        geomMeanLongSun(t) + equationOfCentre(t, meanAnomaly: geomMeanAnomalySun(t))
    }

    /// Apparent longitude (correcting for nutation and aberration, degrees).
    private static func sunApparentLong(_ t: Double) -> Double {
        sunTrueLong(t) - 0.00569 - 0.00478 * sin(toRad(125.04 - 1934.136 * t))
    }

    /// Mean obliquity of the ecliptic (degrees).
    private static func meanObliquityOfEcliptic(_ t: Double) -> Double {
        23.0 + (26.0 + (21.448 - t * (46.8150 + t * (0.00059 - t * 0.001813))) / 60.0) / 60.0
    }

    /// Corrected obliquity (degrees).
    private static func obliquityCorrection(_ t: Double) -> Double {
        meanObliquityOfEcliptic(t) + 0.00256 * cos(toRad(125.04 - 1934.136 * t))
    }

    /// Sun's declination (degrees).
    private static func sunDeclination(_ t: Double) -> Double {
        let lambda = toRad(sunApparentLong(t))
        let e = toRad(obliquityCorrection(t))
        return toDeg(asin(sin(e) * sin(lambda)))
    }

    /// Equation of Time (minutes).
    private static func equationOfTime(_ t: Double) -> Double {
        let e = toRad(obliquityCorrection(t))
        let l0 = toRad(geomMeanLongSun(t))
        let ecc = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let m = toRad(geomMeanAnomalySun(t))
        var y = tan(e / 2); y *= y
        let eqtime = y * sin(2 * l0)
                   - 2 * ecc * sin(m)
                   + 4 * ecc * y * sin(m) * cos(2 * l0)
                   - 0.5 * y * y * sin(4 * l0)
                   - 1.25 * ecc * ecc * sin(2 * m)
        return toDeg(eqtime) * 4.0  // radians -> minutes
    }

    /// Hour angle at sunrise/sunset for given latitude and declination.
    /// Returns nil if sun never rises or never sets at this latitude/date.
    private static func hourAngleSunrise(latitude: Double, declination: Double) -> Double? {
        let latRad = toRad(latitude)
        let decRad = toRad(declination)
        // Solar zenith at sunrise/sunset: 90.833° (refraction + semi-diameter).
        let zenithRad = toRad(90.833)
        let cosHA = (cos(zenithRad) / (cos(latRad) * cos(decRad))) - tan(latRad) * tan(decRad)
        guard cosHA >= -1.0, cosHA <= 1.0 else { return nil }
        return toDeg(acos(cosHA))
    }

    // MARK: Subsolar-point model (Android parity)

    /// The point on Earth where the sun is directly overhead at `date`.
    ///
    /// Low-precision NOAA approximation (≈ arc-minute accuracy) ported verbatim from
    /// `SolarMath.kt` so the day/night terminator renders identically to Android.
    public static func subsolarPoint(for date: Date) -> GeoPoint {
        let d = julianDay(for: date) - j2000
        let g = 357.529 + 0.98560028 * d            // mean anomaly (deg)
        let q = 280.459 + 0.98564736 * d            // mean longitude (deg)
        let l = q + 1.915 * sin(g * deg) + 0.020 * sin(2 * g * deg) // ecliptic longitude
        let e = 23.439 - 0.00000036 * d             // obliquity (deg)

        let declination = asin(sin(e * deg) * sin(l * deg)) / deg
        let rightAscension = atan2(cos(e * deg) * sin(l * deg), cos(l * deg)) / deg

        // Equation of time (minutes) -> subsolar longitude.
        let eqTimeMinutes = 4.0 * normalizeDegrees180(q - rightAscension)
        // milliseconds-of-day, matching Kotlin `toEpochMilli().mod(86_400_000L)`.
        let millis = date.timeIntervalSince1970 * 1000.0
        let millisOfDay = millis.truncatingRemainder(dividingBy: 86_400_000.0)
        let positiveMillisOfDay = millisOfDay < 0 ? millisOfDay + 86_400_000.0 : millisOfDay
        let utcHours = positiveMillisOfDay / 3_600_000.0
        let subsolarLongitude = normalizeDegrees180(-15.0 * (utcHours - 12.0 + eqTimeMinutes / 60.0))

        return GeoPoint(latitude: declination, longitude: subsolarLongitude)
    }

    /// cos(zenith): > 0 day, = 0 on the terminator, < 0 night.
    public static func cosSolarZenith(latitude: Double, longitude: Double, date: Date) -> Double {
        let sub = subsolarPoint(for: date)
        return sin(latitude * deg) * sin(sub.latitude * deg)
            + cos(latitude * deg) * cos(sub.latitude * deg) * cos((longitude - sub.longitude) * deg)
    }

    /// True when the sun is above the horizon at (`latitude`, `longitude`) for `date`.
    /// Equivalent to the point lying on the sunlit hemisphere centred on the subsolar point.
    public static func isDaylight(latitude: Double, longitude: Double, date: Date) -> Bool {
        cosSolarZenith(latitude: latitude, longitude: longitude, date: date) > 0.0
    }

    // MARK: Public API

    /// Compute sunrise, sunset and current solar elevation for a geographic location.
    ///
    /// - Parameters:
    ///   - date: The instant to evaluate (used for both Julian Day and elevation calculation).
    ///   - latitude: Geographic latitude in decimal degrees (positive = North).
    ///   - longitude: Geographic longitude in decimal degrees (positive = East).
    /// - Returns: A ``SolarInfo`` value; `sunrise`/`sunset` are `nil` in polar-night /
    ///   midnight-sun conditions, with `polarDay`/`polarNight` set accordingly.
    public static func solarInfo(for date: Date, latitude: Double, longitude: Double) -> SolarInfo {
        let jd = julianDay(for: date)
        let t  = julianCentury(jd)

        // 1. Solar elevation at the requested instant.
        let decl       = sunDeclination(t)
        let eqT        = equationOfTime(t)
        let utcHours   = (date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400.0)) / 3600.0
        let trueSolarTime = utcHours * 60.0 + eqT + 4.0 * longitude
        var hourAngle = trueSolarTime / 4.0 - 180.0
        if hourAngle < -180.0 { hourAngle += 360.0 }
        if hourAngle >  180.0 { hourAngle -= 360.0 }

        let latRad  = toRad(latitude)
        let declRad = toRad(decl)
        let haRad   = toRad(hourAngle)

        let sinElev = sin(latRad) * sin(declRad) + cos(latRad) * cos(declRad) * cos(haRad)
        let elevationAngle = toDeg(asin(max(-1.0, min(1.0, sinElev))))
        let currentlyDay = elevationAngle > -0.833  // standard refraction correction

        // 2. Sunrise / sunset for the same calendar day in UTC.
        // Under this file's JD epoch convention (`julianDay`: epoch/86400 + 2440587.5), a Julian
        // Day ending in .5 is UTC 00:00 (midnight), so this is the UTC *midnight* of the target
        // day — not noon. (The historical "UTC noon" comment was wrong and produced sunrise/sunset
        // shifted 12 h earlier than the Android reference.)
        let jdMidnight = floor(jd - 0.5) + 0.5  // JD at UTC 00:00 of the target calendar day
        let tNoon    = julianCentury(jdMidnight)
        let declNoon = sunDeclination(tNoon)
        let eqTNoon  = equationOfTime(tNoon)
        let solarNoonMins = 720.0 - 4.0 * longitude - eqTNoon

        var sunriseDate: Date?
        var sunsetDate:  Date?
        var polarDay = false
        var polarNight = false

        if let haAtRise = hourAngleSunrise(latitude: latitude, declination: declNoon) {
            let sunriseMins = solarNoonMins - haAtRise * 4.0
            let sunsetMins  = solarNoonMins + haAtRise * 4.0
            // `(jdMidnight - 2440587.5) * 86400` is already UTC 00:00 of the target day; do NOT
            // subtract 12 h (the old `- 43200` landed sunrise/sunset on the previous day's noon).
            let utcMidnight = (jdMidnight - 2440587.5) * 86400.0  // JD UTC-midnight -> unix midnight
            sunriseDate = Date(timeIntervalSince1970: utcMidnight + sunriseMins * 60.0)
            sunsetDate  = Date(timeIntervalSince1970: utcMidnight + sunsetMins  * 60.0)
        } else {
            // No horizon crossing: distinguish midnight sun from polar night.
            // The sun is up all day when its noon elevation clears the horizon.
            if currentlyDay {
                polarDay = true
            } else {
                polarNight = true
            }
        }

        return SolarInfo(
            sunrise: sunriseDate,
            sunset:  sunsetDate,
            isDaytime: currentlyDay,
            solarElevationAngle: elevationAngle,
            polarDay: polarDay,
            polarNight: polarNight
        )
    }

    /// Convenience wrapper that returns only whether it is currently daytime.
    ///
    /// - Parameters:
    ///   - date: Instant to evaluate.
    ///   - latitude: Geographic latitude in decimal degrees.
    ///   - longitude: Geographic longitude in decimal degrees.
    /// - Returns: `true` if the solar elevation angle exceeds −0.833°.
    public static func isDaytime(at date: Date, latitude: Double, longitude: Double) -> Bool {
        solarInfo(for: date, latitude: latitude, longitude: longitude).isDaytime
    }
}

// MARK: - ZoneCoordinates

/// Maps IANA timezone identifiers to representative geographic coordinates.
///
/// The coordinates correspond to the primary city for the timezone and are suitable
/// for solar calculations (sunrise/sunset, day/night determination).
///
/// This type is a thin compatibility shim retained for its callers (e.g. `TimeEngine`): the
/// data lives in the single canonical table `ZoneGeo.known` (the full IANA set). Previously this
/// struct embedded its own ~80-city table, which could disagree with `ZoneGeo` and the location
/// resolver and yield inconsistent day/night, globe and home-zone results. `coordinates(for:)`
/// now delegates to `ZoneGeo` so there is exactly one source of truth.
public struct ZoneCoordinates: Sendable {

    /// Returns the representative (latitude, longitude) for a given IANA timezone ID,
    /// or `nil` if the timezone is not in the canonical ``ZoneGeo`` table.
    ///
    /// - Parameter tzId: An IANA timezone identifier, e.g. `"America/New_York"`.
    /// - Returns: A named tuple `(lat: Double, lon: Double)` in decimal degrees, or `nil`.
    public static func coordinates(for tzId: String) -> (lat: Double, lon: Double)? {
        ZoneGeo.coordinates(for: tzId)
    }
}
