// SolarDaylightWidget.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// Ported from the `SolarDaylightWidget` composable in `NowScreen.kt`.
//
// A glass card summarising solar state for one zone: day/night status, sunrise &
// sunset times, a `SunTrackView` progress bar, and a "N hrs M mins of daylight"
// summary (with polar-day / polar-night special cases).

import Foundation
import SwiftUI

// MARK: - SunTimes (Android-parity sunrise/sunset)

/// Sunrise/sunset wall-clock times for a date, expressed as minute-of-day (0–1439) in
/// the target zone, with explicit polar-day/night flags. Mirrors Android `SunTimes`.
struct SunTimes: Sendable {
    /// Sunrise as minute-of-day in the target zone; `nil` for polar day/night.
    let sunriseMinute: Int?
    /// Sunset as minute-of-day in the target zone; `nil` for polar day/night.
    let sunsetMinute: Int?
    let polarDay: Bool
    let polarNight: Bool
}

extension SolarMath {

    private static let deg2 = Double.pi / 180.0
    private static let j2000_2 = 2451545.0

    private static func julianDayMillis(_ instant: Date) -> Double {
        instant.timeIntervalSince1970 * 1000.0 / 86_400_000.0 + 2_440_587.5
    }

    private static func normalizeDeg180(_ deg: Double) -> Double {
        var v = deg.truncatingRemainder(dividingBy: 360.0)
        if v > 180.0 { v -= 360.0 }
        if v < -180.0 { v += 360.0 }
        return v
    }

    /// Local-noon instant of `localDate` in `zone` (matching Android
    /// `date.atTime(LocalTime.NOON).atZone(zone).toInstant()`).
    private static func localNoonInstant(localDate: Date, zone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let comps = cal.dateComponents([.year, .month, .day], from: localDate)
        var noon = DateComponents()
        noon.year = comps.year
        noon.month = comps.month
        noon.day = comps.day
        noon.hour = 12
        noon.minute = 0
        noon.second = 0
        return cal.date(from: noon) ?? localDate
    }

    /// Subsolar latitude (declination, degrees) — exact port of `SolarMath.kt` `subsolarPoint`.
    private static func subsolarLatitude(_ instant: Date) -> Double {
        let d = julianDayMillis(instant) - j2000_2
        let g = 357.529 + 0.98560028 * d
        let q = 280.459 + 0.98564736 * d
        let l = q + 1.915 * sin(g * deg2) + 0.020 * sin(2 * g * deg2)
        let e = 23.439 - 0.00000036 * d
        return asin(sin(e * deg2) * sin(l * deg2)) / deg2
    }

    /// Sunrise/sunset wall-clock minute-of-day in `zone` for the zone-local `localDate`.
    ///
    /// Exact port of Android `SolarMath.sunTimes(latitude, longitude, date, zone)`:
    /// declination from the subsolar point at local-noon of the target zone, equation of
    /// time without the `0.020*sin(2g)` term, then ±4·hourAngle around solar noon.
    static func sunTimes(latitude: Double, longitude: Double, localDate: Date, zone: TimeZone) -> SunTimes {
        let noonInstant = localNoonInstant(localDate: localDate, zone: zone)
        let declination = subsolarLatitude(noonInstant)

        let zenith = 90.833 * deg2 // atmospheric refraction + sun radius
        let cosHourAngle = (cos(zenith) - sin(latitude * deg2) * sin(declination * deg2)) /
            (cos(latitude * deg2) * cos(declination * deg2))

        if cosHourAngle > 1.0 { return SunTimes(sunriseMinute: nil, sunsetMinute: nil, polarDay: false, polarNight: true) }
        if cosHourAngle < -1.0 { return SunTimes(sunriseMinute: nil, sunsetMinute: nil, polarDay: true, polarNight: false) }

        let hourAngle = acos(cosHourAngle) / deg2 // degrees

        // Equation of time at noon, in minutes (note: no 0.020*sin(2g) term, matching Android).
        let d = julianDayMillis(noonInstant) - j2000_2
        let q = 280.459 + 0.98564736 * d
        let gLong = q + 1.915 * sin((357.529 + 0.98560028 * d) * deg2)
        let e = 23.439 - 0.00000036 * d
        let ra = atan2(cos(e * deg2) * sin(gLong * deg2), cos(gLong * deg2)) / deg2
        let eqTimeMinutes = 4.0 * normalizeDeg180(q - ra)

        let solarNoonUtcMinutes = 720.0 - 4.0 * longitude - eqTimeMinutes
        let sunriseUtcMinutes = solarNoonUtcMinutes - 4.0 * hourAngle
        let sunsetUtcMinutes = solarNoonUtcMinutes + 4.0 * hourAngle

        return SunTimes(
            sunriseMinute: utcMinutesToZoneMinute(localDate: localDate, utcMinutes: sunriseUtcMinutes, zone: zone),
            sunsetMinute: utcMinutesToZoneMinute(localDate: localDate, utcMinutes: sunsetUtcMinutes, zone: zone),
            polarDay: false,
            polarNight: false
        )
    }

    /// Port of Android `utcMinutesToLocalTime`: builds the UTC instant at
    /// `localDate` start-of-day-UTC + wrapped minutes, then reads its wall-clock
    /// minute-of-day in `zone`.
    private static func utcMinutesToZoneMinute(localDate: Date, utcMinutes: Double, zone: TimeZone) -> Int {
        let wrapped = ((utcMinutes.truncatingRemainder(dividingBy: 1440.0)) + 1440.0).truncatingRemainder(dividingBy: 1440.0)

        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        var zoneCal = Calendar(identifier: .gregorian)
        zoneCal.timeZone = zone
        // Day-of-month comes from the zone-local date (Android uses the LocalDate directly).
        let dc = zoneCal.dateComponents([.year, .month, .day], from: localDate)

        var midnightUTC = DateComponents()
        midnightUTC.year = dc.year
        midnightUTC.month = dc.month
        midnightUTC.day = dc.day
        midnightUTC.hour = 0
        midnightUTC.minute = 0
        midnightUTC.second = 0
        let startOfDayUTC = utcCal.date(from: midnightUTC) ?? localDate
        let instant = startOfDayUTC.addingTimeInterval(wrapped * 60.0)

        let c = zoneCal.dateComponents([.hour, .minute], from: instant)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

// MARK: - SolarDaylightWidget

struct SolarDaylightWidget: View {

    /// IANA zone id the solar geometry is computed for.
    let zoneId: String
    /// Absolute instant to render (from TimeEngine.displayDate).
    let date: Date
    let use24Hour: Bool

    // MARK: Derived solar state

    private var timeZone: TimeZone { TimeFormats.safeTimeZone(id: zoneId) }

    private var coordinate: GeoPoint {
        ZoneGeo.coordinate(for: zoneId, at: date)
    }

    /// Android-parity sunrise/sunset for the target zone's local date.
    private var sun: SunTimes {
        SolarMath.sunTimes(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            localDate: date,
            zone: timeZone
        )
    }

    private var isDaylight: Bool {
        SolarMath.isDaylight(
            latitude: coordinate.latitude, longitude: coordinate.longitude, date: date
        )
    }

    private var glowColor: Color {
        isDaylight ? MeridianColors.daylightGlow : MeridianColors.nightGlow
    }

    private var accentColor: Color {
        isDaylight ? MeridianColors.daylightAccent : MeridianColors.nightAccent
    }

    /// Formats a zone-local minute-of-day as an "h:mm a" / "HH:mm" string.
    private func sunString(_ minute: Int?) -> String? {
        guard let minute else { return nil }
        guard let d = SolarDaylightWidget.dateForZoneMinute(minute, reference: date, zone: timeZone) else { return nil }
        return TimeFormats.hourMinute(date: d, timeZone: timeZone, use24Hour: use24Hour)
    }

    private var daylightSummary: String {
        if let rise = sun.sunriseMinute, let set = sun.sunsetMinute {
            // Mirrors Android Duration.between(sunrise, sunset) on LocalTimes.
            let totalMinutes = set - rise
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return "\(hours) hrs \(minutes) mins of daylight today"
        } else if sun.polarDay {
            return "Midnight Sun (24 hrs daylight)"
        } else {
            return "Polar Night (24 hrs darkness)"
        }
    }

    /// Builds a `Date` whose wall-clock time in `zone` is `minute` (0–1439) on the
    /// `reference` instant's zone-local calendar day. Only hour/minute are meaningful.
    static func dateForZoneMinute(_ minute: Int, reference: Date, zone: TimeZone) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        var comps = cal.dateComponents([.year, .month, .day], from: reference)
        comps.hour = minute / 60
        comps.minute = minute % 60
        comps.second = 0
        return cal.date(from: comps)
    }

    // MARK: Accessibility

    /// One coherent VoiceOver announcement for the whole card: status, then
    /// spelled-out sunrise/sunset (never the raw ↑/↓ glyphs), then daylight summary.
    private var accessibilityDescription: String {
        let status = isDaylight ? "Currently daylight." : "Currently nighttime."
        var parts: [String] = [status]
        if let rise = sunString(sun.sunriseMinute), let set = sunString(sun.sunsetMinute) {
            parts.append("Sunrise \(rise), sunset \(set).")
        }
        parts.append(daylightSummary + ".")
        return parts.joined(separator: " ")
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row: status icon + title + subtitle + sun arrows.
            HStack(alignment: .top, spacing: MeridianSpacing.md.rawValue) {
                Image(systemName: isDaylight ? "sun.max.fill" : "moon.stars.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(accentColor)
                    .shadow(color: accentColor.opacity(0.6), radius: 4)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: MeridianSpacing.xs.rawValue) {
                    Text(isDaylight ? "Sunlight Status" : "Nighttime Status")
                        .font(.titleMedium)
                        .foregroundStyle(MeridianColors.onSurface)

                    Text(isDaylight ? "Currently Daylight" : "Currently Nighttime")
                        .font(.bodyMedium)
                        .foregroundStyle(MeridianColors.onSurfaceVariant)

                    if let rise = sunString(sun.sunriseMinute), let set = sunString(sun.sunsetMinute) {
                        HStack(spacing: MeridianSpacing.sm.rawValue) {
                            Label(rise, systemImage: "sunrise.fill")
                                .labelStyle(.titleAndIcon)
                            Label(set, systemImage: "sunset.fill")
                                .labelStyle(.titleAndIcon)
                        }
                        .font(.labelMedium)
                        .foregroundStyle(MeridianColors.primary)
                        .padding(.top, MeridianSpacing.xs.rawValue / 2)
                        .accessibilityHidden(true)
                    }
                }

                Spacer(minLength: 0)
            }

            // Sun progress track.
            SunTrackView(
                sunriseMinutes: sun.sunriseMinute,
                sunsetMinutes: sun.sunsetMinute,
                currentMinutes: SunTrackView.minutesOfDay(of: date, in: timeZone) ?? 0,
                polarDay: sun.polarDay,
                polarNight: sun.polarNight
            )
            .padding(.top, MeridianSpacing.lg.rawValue) // header → track (was Spacer 16)

            Text(daylightSummary)
                .font(.labelMedium)
                .foregroundStyle(MeridianColors.onSurfaceVariant.opacity(0.8))
                .padding(.top, MeridianSpacing.sm.rawValue) // track → summary (was Spacer 8)
                .accessibilityHidden(true)
        }
        .padding(MeridianSpacing.lg.rawValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(
            cornerRadius: MeridianRadius.medium.rawValue,
            tint: MeridianColors.nightAccent
        )
        // Corner glow (Android drawBehind radial gradient at 85%/15%).
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [glowColor.opacity(0.22), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 90
                    )
                )
                .frame(width: 180, height: 180)
                .offset(x: 40, y: -40)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: MeridianRadius.medium.rawValue, style: .continuous))
        // One coherent announcement for the whole solar card instead of ambiguous
        // arrow glyphs plus a hidden track.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("SolarDaylightWidget", traits: .sizeThatFitsLayout) {
    SolarDaylightWidget(zoneId: "America/New_York", date: Date(), use24Hour: false)
        .padding()
        .background(MeridianColors.background)
        .environment(\.glassEnabled, true)
}
#endif
