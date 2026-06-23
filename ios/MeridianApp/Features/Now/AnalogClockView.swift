// AnalogClockView.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// Ported from the `AnalogClock` Canvas composable in `NowScreen.kt`.
//
// Draws a small analog clock face (ticks + hour/minute/second hands) for an
// absolute instant rendered in a given time zone. The hands are computed from
// the wall-clock components of `date` in `timeZone`, so the same instant renders
// correctly for any zone (this is the VIEW layer's job per the time contract —
// the model never bakes a zone-local string).

import SwiftUI

// MARK: - AnalogClockView

/// A compact analog clock matching the Android `AnalogClock` Canvas.
///
/// Default diameter is 100pt (Android `Modifier.size(100.dp)`). Hand lengths,
/// stroke widths, and tick geometry mirror the Android drawing exactly.
struct AnalogClockView: View {

    /// Absolute instant to display.
    let date: Date
    /// Time zone whose wall-clock the hands represent.
    let timeZone: TimeZone
    /// Diameter of the clock face in points.
    var diameter: CGFloat = 100

    // Theme colors (Android: primary / secondary / tertiary / onSurface).
    private let hourColor: Color = MeridianColors.primary
    private let minuteColor: Color = MeridianColors.secondary
    // Android `tertiary` has no token; nightAccent is the closest cool accent.
    private let secondColor: Color = MeridianColors.nightAccent
    private let faceColor: Color = MeridianColors.onSurface

    // MARK: Time components

    private var components: (hour: Int, minute: Int, second: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        return (c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    // MARK: Body

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width / 2
            let degToRad = CGFloat.pi / 180

            // Clock face outline.
            let faceRect = CGRect(
                x: center.x - radius + 1,
                y: center.y - radius + 1,
                width: (radius - 1) * 2,
                height: (radius - 1) * 2
            )
            context.stroke(
                Circle().path(in: faceRect),
                with: .color(faceColor.opacity(0.15)),
                lineWidth: 2
            )

            // Ticks: 12 marks, every third is a major tick.
            for i in 0..<12 {
                let angle = CGFloat(i) * 30 * degToRad
                let isMain = i % 3 == 0
                let tickLength: CGFloat = isMain ? 8 : 4
                let outer = CGPoint(
                    x: center.x + (radius - 2) * sin(angle),
                    y: center.y - (radius - 2) * cos(angle)
                )
                let inner = CGPoint(
                    x: center.x + (radius - tickLength - 2) * sin(angle),
                    y: center.y - (radius - tickLength - 2) * cos(angle)
                )
                var tick = Path()
                tick.move(to: outer)
                tick.addLine(to: inner)
                context.stroke(
                    tick,
                    with: .color(faceColor.opacity(isMain ? 0.5 : 0.2)),
                    style: StrokeStyle(lineWidth: isMain ? 2 : 1, lineCap: .round)
                )
            }

            let (hour24, minute, second) = components
            let hour = hour24 % 12

            let hourAngle = (CGFloat(hour) + CGFloat(minute) / 60) * 30 * degToRad
            let minuteAngle = (CGFloat(minute) + CGFloat(second) / 60) * 6 * degToRad
            let secondAngle = CGFloat(second) * 6 * degToRad

            func hand(length: CGFloat, angle: CGFloat) -> Path {
                var p = Path()
                p.move(to: center)
                p.addLine(to: CGPoint(
                    x: center.x + length * sin(angle),
                    y: center.y - length * cos(angle)
                ))
                return p
            }

            // Hour hand (0.5 r).
            context.stroke(
                hand(length: radius * 0.5, angle: hourAngle),
                with: .color(hourColor),
                style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
            )
            // Minute hand (0.75 r).
            context.stroke(
                hand(length: radius * 0.75, angle: minuteAngle),
                with: .color(minuteColor),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
            // Second hand (0.85 r).
            context.stroke(
                hand(length: radius * 0.85, angle: secondAngle),
                with: .color(secondColor),
                style: StrokeStyle(lineWidth: 1, lineCap: .round)
            )

            // Center pin.
            let pinRadius: CGFloat = 3
            let pinRect = CGRect(
                x: center.x - pinRadius,
                y: center.y - pinRadius,
                width: pinRadius * 2,
                height: pinRadius * 2
            )
            context.fill(Circle().path(in: pinRect), with: .color(secondColor))
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

// MARK: - Convenience init

extension AnalogClockView {
    /// Convenience initialiser taking an IANA zone id; falls back to the current zone.
    init(date: Date, timeZoneId: String, diameter: CGFloat = 100) {
        self.init(
            date: date,
            timeZone: TimeFormats.safeTimeZone(id: timeZoneId),
            diameter: diameter
        )
    }
}

// MARK: - Previews

#if DEBUG
#Preview("AnalogClockView", traits: .sizeThatFitsLayout) {
    HStack(spacing: 24) {
        AnalogClockView(date: Date(), timeZoneId: "America/New_York")
        AnalogClockView(date: Date(), timeZoneId: "Asia/Tokyo")
    }
    .padding()
    .background(MeridianColors.background)
}
#endif
