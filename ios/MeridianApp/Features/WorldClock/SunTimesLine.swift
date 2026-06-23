//  SunTimesLine.swift
//  Meridian — iOS 27 / Swift 6
//
//  Ported from the `SunTimesLine` composable in WorldClockScreen.kt (§5.9).
//
//  A single compact line under each zone row showing today's sunrise / sunset, or a polar
//  day/night message when the sun never crosses the horizon.
//
//  Solar model parity: Android's `SunTimesLine` calls `SolarMath.sunTimes(...)` — the
//  LOW-precision subsolar-point model (declination from the subsolar point at local noon;
//  hour angle solved against zenith 90.833° via `(cos z - sin·sin) / (cos·cos)`; equation of
//  time from `4·normalizeDegrees180(q − RA)`). The high-precision NOAA/Meeus path exposed by
//  `SolarMath.solarInfo` produces *different* sunrise/sunset values, so this view ports
//  Android's `sunTimes` verbatim (below) and uses it, matching Android pixel-for-pixel.

import SwiftUI

struct SunTimesLine: View {

    let zoneId: String
    /// Shared display instant (scrub-aware); the calendar day is taken in `zoneId`.
    let instant: Date
    let use24Hour: Bool
    var textColor: Color = MeridianColors.onSurface

    var body: some View {
        Text(label)
            .font(.system(size: 10))
            .foregroundStyle(textColor.opacity(0.6))
            .padding(.top, 2)
    }

    // MARK: - Computed

    private var coordinate: GeoPoint {
        ZoneGeo.coordinate(for: zoneId, at: instant)
    }

    /// Sunrise/sunset for the zone-local calendar day containing `instant`.
    ///
    /// Mirrors Android `SolarMath.sunTimes(coord.lat, coord.lng, time.toLocalDate(), time.zone)`.
    private var sun: SunTimesResult {
        SunTimesLine.sunTimes(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            instant: instant,
            zoneId: zoneId
        )
    }

    private var label: String {
        let s = sun
        if s.polarDay {
            return "☀️ Midnight sun — no sunset"
        }
        if s.polarNight {
            return "🌑 Polar night — no sunrise"
        }
        if let sunrise = s.sunrise, let sunset = s.sunset {
            let rise = TimeFormats.hourMinute(date: sunrise, timeZoneId: zoneId, use24Hour: use24Hour)
            let set  = TimeFormats.hourMinute(date: sunset,  timeZoneId: zoneId, use24Hour: use24Hour)
            return "🌅 \(rise)   🌇 \(set)"
        }
        return "Sun times unavailable"
    }

    // MARK: - Android `SolarMath.sunTimes` port (subsolar-point model, zenith 90.833°)

    /// Result of the low-precision sun-times calculation, mirroring Android's `SunTimes`.
    private struct SunTimesResult {
        let sunrise: Date?
        let sunset: Date?
        var polarDay: Bool = false
        var polarNight: Bool = false
    }

    private static let deg = Double.pi / 180.0
    private static let j2000 = 2451545.0

    /// Normalises an angle in degrees into the half-open range (-180, 180].
    /// Verbatim port of Android `SolarMath.normalizeDegrees180`.
    private static func normalizeDegrees180(_ deg: Double) -> Double {
        var v = deg.truncatingRemainder(dividingBy: 360.0)
        if v > 180.0 { v -= 360.0 }
        if v < -180.0 { v += 360.0 }
        return v
    }

    /// Sunrise/sunset wall-clock times for the zone-local day containing `instant`.
    ///
    /// Verbatim port of Android `SolarMath.sunTimes(latitude, longitude, date, zone)`, where
    /// `date` is the zone-local calendar day and `zone` is `zoneId`. Returns polar flags when
    /// the sun never crosses the horizon.
    private static func sunTimes(
        latitude: Double,
        longitude: Double,
        instant: Date,
        zoneId: String
    ) -> SunTimesResult {
        let tz = TimeFormats.safeTimeZone(id: zoneId)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz

        // Local noon of the zone-day = `date.atTime(LocalTime.NOON).atZone(zone).toInstant()`.
        let startOfDay = cal.startOfDay(for: instant)
        let noonInstant = cal.date(byAdding: .hour, value: 12, to: startOfDay) ?? instant

        // Declination from the subsolar point at local noon (Android parity model).
        let declination = SolarMath.subsolarPoint(for: noonInstant).latitude

        let zenith = 90.833 * deg // includes atmospheric refraction + sun radius
        let cosHourAngle = (cos(zenith) - sin(latitude * deg) * sin(declination * deg)) /
            (cos(latitude * deg) * cos(declination * deg))

        if cosHourAngle > 1.0 {
            return SunTimesResult(sunrise: nil, sunset: nil, polarNight: true)  // sun never rises
        }
        if cosHourAngle < -1.0 {
            return SunTimesResult(sunrise: nil, sunset: nil, polarDay: true)     // sun never sets
        }

        let hourAngle = acos(cosHourAngle) / deg // degrees

        // Equation of time at noon, in minutes.
        let d = (noonInstant.timeIntervalSince1970 / 86_400.0 + 2440587.5) - j2000
        let q = 280.459 + 0.98564736 * d
        let gLong = q + 1.915 * sin((357.529 + 0.98560028 * d) * deg)
        let e = 23.439 - 0.00000036 * d
        let ra = atan2(cos(e * deg) * sin(gLong * deg), cos(gLong * deg)) / deg
        let eqTimeMinutes = 4.0 * normalizeDegrees180(q - ra)

        // Solar noon in UTC minutes for this longitude, then convert each event to the zone.
        let solarNoonUtcMinutes = 720.0 - 4.0 * longitude - eqTimeMinutes
        let sunriseUtcMinutes = solarNoonUtcMinutes - 4.0 * hourAngle
        let sunsetUtcMinutes = solarNoonUtcMinutes + 4.0 * hourAngle

        // Android anchors events on `date.atStartOfDay(ZoneOffset.UTC)`, i.e. the zone-local
        // calendar day's UTC midnight. Reconstruct that instant from the zone-local Y/M/D.
        let dayComps = cal.dateComponents([.year, .month, .day], from: startOfDay)
        let utcMidnight = utcMidnightInstant(year: dayComps.year, month: dayComps.month, day: dayComps.day)
            ?? startOfDay

        return SunTimesResult(
            sunrise: utcMinutesToDate(utcMidnight: utcMidnight, utcMinutes: sunriseUtcMinutes),
            sunset:  utcMinutesToDate(utcMidnight: utcMidnight, utcMinutes: sunsetUtcMinutes)
        )
    }

    /// UTC-midnight instant for the given calendar date, mirroring Android
    /// `date.atStartOfDay(ZoneOffset.UTC)`.
    private static func utcMidnightInstant(year: Int?, month: Int?, day: Int?) -> Date? {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return utcCal.date(from: comps)
    }

    /// Maps a UTC-minutes offset to an absolute instant, mirroring Android
    /// `utcMinutesToLocalTime`: wrap into `[0, 1440)`, anchor at the day's UTC midnight, then add
    /// the wrapped minutes. The downstream formatter renders it in `zoneId`, matching Android's
    /// `ZonedDateTime.ofInstant(instant, zone).toLocalTime()`.
    private static func utcMinutesToDate(utcMidnight: Date, utcMinutes: Double) -> Date {
        let wrapped = (utcMinutes.truncatingRemainder(dividingBy: 1440.0) + 1440.0)
            .truncatingRemainder(dividingBy: 1440.0)
        return utcMidnight.addingTimeInterval(wrapped * 60.0)
    }
}
