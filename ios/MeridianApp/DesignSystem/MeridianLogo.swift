// MeridianLogo.swift
// Meridian — iOS 27 / Swift 6
//
// Ported from app/src/main/java/com/example/core/designsystem/MeridianLogo.kt
//
// Brand mark — a wireframe globe (prime meridian + equator + curved longitude /
// latitude lines) with a "solar noon" marker where the prime meridian crosses the
// rim — rendered with SwiftUI `Canvas`. Theme-aware via `lineColor` / `markerColor`,
// defaulting to the Meridian primary and night accents.

import SwiftUI

/// The Meridian wireframe-globe logo.
struct MeridianLogo: View {
    var size: CGFloat = 32
    var lineColor: Color = MeridianColors.primary
    /// Android uses the Material `tertiary` accent; the Meridian iOS palette uses the
    /// night accent as the tertiary-equivalent solar-noon marker tint.
    var markerColor: Color = MeridianColors.nightAccent

    var body: some View {
        Canvas { context, canvasSize in
            let w = min(canvasSize.width, canvasSize.height)
            let center = CGPoint(x: w / 2, y: w / 2)
            let radius = w * 0.40
            let strokeWidth = w * 0.055
            let stroke = StrokeStyle(lineWidth: strokeWidth, lineCap: .round)

            // Globe rim
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2)),
                with: .color(lineColor),
                style: stroke
            )

            // Equator (horizontal diameter)
            var equator = Path()
            equator.move(to: CGPoint(x: center.x - radius, y: center.y))
            equator.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            context.stroke(equator, with: .color(lineColor), style: stroke)

            // Prime meridian (vertical diameter)
            var meridian = Path()
            meridian.move(to: CGPoint(x: center.x, y: center.y - radius))
            meridian.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            context.stroke(meridian, with: .color(lineColor), style: stroke)

            // Curved meridian (longitude ellipse)
            let meridianHalfWidth = radius * 0.42
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: center.x - meridianHalfWidth, y: center.y - radius,
                    width: meridianHalfWidth * 2, height: radius * 2)),
                with: .color(lineColor),
                style: stroke
            )

            // Curved latitude (ellipse)
            let latitudeHalfHeight = radius * 0.42
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: center.x - radius, y: center.y - latitudeHalfHeight,
                    width: radius * 2, height: latitudeHalfHeight * 2)),
                with: .color(lineColor),
                style: stroke
            )

            // Solar-noon marker where the prime meridian meets the rim
            let markerRadius = w * 0.085
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - markerRadius, y: center.y - radius - markerRadius,
                    width: markerRadius * 2, height: markerRadius * 2)),
                with: .color(markerColor)
            )
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Meridian logo")
    }
}

/// Logo + "Meridian" wordmark, laid out horizontally for headers and brand surfaces.
struct MeridianWordmark: View {
    var logoSize: CGFloat = 28

    var body: some View {
        HStack(spacing: 10) {
            MeridianLogo(size: logoSize)
            Text("Meridian")
                .font(.system(size: 22, weight: .black))   // titleLarge + Black
                .foregroundStyle(MeridianColors.onBackground)
        }
    }
}

#if DEBUG
#Preview("MeridianLogo", traits: .sizeThatFitsLayout) {
    VStack(spacing: 24) {
        MeridianLogo(size: 64)
        MeridianWordmark(logoSize: 32)
    }
    .padding()
    .background(MeridianColors.background)
}
#endif
