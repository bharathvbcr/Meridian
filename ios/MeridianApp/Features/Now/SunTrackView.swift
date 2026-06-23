// SunTrackView.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// Ported from the `SunTrackCanvas` composable in `NowScreen.kt`.
//
// A horizontal progress track that places a sun/moon node along a line according
// to how far through the daylight (or night) span the current wall-clock time is.
// Handles polar day / polar night by centering a static node.
//
// All times are minutes-of-day (0–1439) in the *target zone*; the caller resolves
// sunrise/sunset/current into that zone, keeping the model free of zone-local state.

import SwiftUI

// MARK: - SunTrackView

struct SunTrackView: View {

    /// Sunrise minute-of-day in the target zone, or `nil` (polar day/night).
    let sunriseMinutes: Int?
    /// Sunset minute-of-day in the target zone, or `nil` (polar day/night).
    let sunsetMinutes: Int?
    /// Current minute-of-day in the target zone.
    let currentMinutes: Int
    /// Sun never sets today.
    let polarDay: Bool
    /// Sun never rises today.
    let polarNight: Bool

    private let trackColor = MeridianColors.onSurface.opacity(0.15)
    private let daylightColor = MeridianColors.daylightAccent.opacity(0.8)
    private let nightColor = MeridianColors.nightAccent.opacity(0.8)

    /// Node tint: daylight when current time falls between sunrise and sunset, else night.
    private var dotColor: Color {
        if let rise = sunriseMinutes, let set = sunsetMinutes,
           currentMinutes > rise, currentMinutes < set {
            return MeridianColors.daylightAccent
        }
        return MeridianColors.nightAccent
    }

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let centerY = size.height / 2

            // Background line.
            var bg = Path()
            bg.move(to: CGPoint(x: 0, y: centerY))
            bg.addLine(to: CGPoint(x: width, y: centerY))
            context.stroke(
                bg,
                with: .color(trackColor),
                style: StrokeStyle(lineWidth: 4, lineCap: .round)
            )

            var pct: CGFloat = 0
            var isSpecialState = false
            var specialColor = trackColor

            if polarDay {
                pct = 0.5
                isSpecialState = true
                specialColor = daylightColor
            } else if polarNight {
                pct = 0.5
                isSpecialState = true
                specialColor = nightColor
            } else if let riseMin = sunriseMinutes, let setMin = sunsetMinutes {
                let currentMin = currentMinutes
                if currentMin >= riseMin && currentMin <= setMin {
                    // Daylight progress.
                    let range = setMin - riseMin
                    pct = clamp(range > 0 ? CGFloat(currentMin - riseMin) / CGFloat(range) : 0)
                    var seg = Path()
                    seg.move(to: CGPoint(x: 0, y: centerY))
                    seg.addLine(to: CGPoint(x: pct * width, y: centerY))
                    context.stroke(
                        seg,
                        with: .color(daylightColor),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                } else {
                    // Nighttime progress.
                    let elapsed: Int = currentMin < riseMin
                        ? (1440 - setMin) + currentMin
                        : currentMin - setMin
                    let totalNight = 1440 - (setMin - riseMin)
                    pct = clamp(totalNight > 0 ? CGFloat(elapsed) / CGFloat(totalNight) : 0)
                    var seg = Path()
                    seg.move(to: CGPoint(x: 0, y: centerY))
                    seg.addLine(to: CGPoint(x: pct * width, y: centerY))
                    context.stroke(
                        seg,
                        with: .color(nightColor),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                }
            }

            // Sun / moon node.
            if isSpecialState {
                let r: CGFloat = 6
                let rect = CGRect(x: width / 2 - r, y: centerY - r, width: r * 2, height: r * 2)
                context.fill(Circle().path(in: rect), with: .color(specialColor))
            } else {
                let nodeX = pct * width
                let r: CGFloat = 7
                let rect = CGRect(x: nodeX - r, y: centerY - r, width: r * 2, height: r * 2)
                context.fill(Circle().path(in: rect), with: .color(dotColor))
                // Glowing ring.
                let ringR: CGFloat = 11
                let ringRect = CGRect(
                    x: nodeX - ringR, y: centerY - ringR, width: ringR * 2, height: ringR * 2
                )
                context.stroke(
                    Circle().path(in: ringRect),
                    with: .color(dotColor.opacity(0.3)),
                    lineWidth: 2
                )
            }
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func clamp(_ v: CGFloat) -> CGFloat { min(max(v, 0), 1) }
}

// MARK: - Minute-of-day helper

extension SunTrackView {
    /// Minute-of-day (0–1439) for `date` in `timeZone`.
    static func minutesOfDay(of date: Date?, in timeZone: TimeZone) -> Int? {
        guard let date else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("SunTrackView", traits: .sizeThatFitsLayout) {
    VStack(spacing: 16) {
        SunTrackView(sunriseMinutes: 360, sunsetMinutes: 1200, currentMinutes: 780,
                     polarDay: false, polarNight: false)
        SunTrackView(sunriseMinutes: 360, sunsetMinutes: 1200, currentMinutes: 60,
                     polarDay: false, polarNight: false)
        SunTrackView(sunriseMinutes: nil, sunsetMinutes: nil, currentMinutes: 720,
                     polarDay: true, polarNight: false)
    }
    .padding()
    .background(MeridianColors.background)
}
#endif
