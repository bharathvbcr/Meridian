// WatchlistZoneCard.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// Ported from the `WatchlistZoneCard` composable in `NowScreen.kt`.
//
// A glass card for one watchlist zone showing local time (via TimeEngine), a
// working-hours tint, a daylight/night corner glow, favorite-contact pills, and an
// expandable detail section (sunrise/sunset, work window, IANA id, contact management).
// An overflow menu exposes favorite/add-contact/set-home/move/delete actions.

import SwiftUI

// MARK: - WatchlistZoneCard

struct WatchlistZoneCard: View {

    // Data
    let zone: SavedZone
    /// Absolute instant to render (TimeEngine.displayDate).
    let date: Date
    let use24Hour: Bool
    let isFirst: Bool
    let isLast: Bool
    let workStartHour: Int
    let workEndHour: Int
    /// Starred contacts that appear on this zone's row.
    let contacts: [Person]

    // Callbacks (wired to MainViewModel by NowScreen).
    var onAddContact: (String) -> Void = { _ in }
    var onRemoveContact: (UUID) -> Void = { _ in }
    var onToggleContactFavorite: (UUID) -> Void = { _ in }
    var onToggleZoneFavorite: () -> Void = {}
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}
    var onSetHome: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var expanded = false
    @State private var showAddContact = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Derived

    private var timeZone: TimeZone { TimeFormats.safeTimeZone(id: zone.id) }

    private var zoneHour: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.component(.hour, from: date)
    }

    private var isWorkingHours: Bool {
        zoneHour >= workStartHour && zoneHour < workEndHour
    }

    private var coordinate: GeoPoint { ZoneGeo.coordinate(for: zone.id, at: date) }

    private var isDaylight: Bool {
        SolarMath.isDaylight(
            latitude: coordinate.latitude, longitude: coordinate.longitude, date: date
        )
    }

    private var glowColor: Color {
        isDaylight ? MeridianColors.daylightGlow : MeridianColors.nightGlow
    }

    private var tintColor: Color {
        isWorkingHours ? MeridianColors.primary : MeridianColors.secondary
    }

    private var timeString: String {
        TimeFormats.hourMinute(date: date, timeZone: timeZone, use24Hour: use24Hour)
    }

    private var dateString: String {
        TimeFormats.shortDate(date: date, timeZoneId: zone.id)
    }

    private var utcOffsetString: String {
        TimeFormats.utcOffset(for: zone.id, at: date)
    }

    private var favoriteContacts: [Person] { contacts.filter(\.isFavorite) }

    /// Android-parity sunrise/sunset for this zone's local date.
    private var sun: SunTimes {
        SolarMath.sunTimes(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            localDate: date,
            zone: timeZone
        )
    }

    private func sunString(_ minute: Int?) -> String? {
        guard let minute else { return nil }
        guard let d = SolarDaylightWidget.dateForZoneMinute(minute, reference: date, zone: timeZone) else { return nil }
        return TimeFormats.hourMinute(date: d, timeZone: timeZone, use24Hour: use24Hour)
    }

    /// Combined VoiceOver label for the collapsed header: zone, local time, and work status.
    private var headerAccessibilityLabel: String {
        var parts = [zone.displayName]
        if zone.isFavorite { parts.append("Favorite") }
        parts.append(isDaylight ? "daytime" : "night")
        parts.append("\(timeString), \(dateString), \(utcOffsetString)")
        parts.append(isWorkingHours ? "Working hours" : "Off hours")
        return parts.joined(separator: ", ")
    }

    /// Toggles the expanded state. Animation is applied once at the view level via
    /// `.animation(_:value: expanded)` (gated on Reduce Motion), so this only mutates
    /// state — no `withAnimation` here, to avoid a redundant double-spring.
    private func toggleExpanded() {
        expanded.toggle()
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: MeridianSpacing.md.rawValue) {
                headerInfo
                    .contentShape(Rectangle())
                    .onTapGesture { toggleExpanded() }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(headerAccessibilityLabel)
                    .accessibilityHint(expanded ? "Collapse zone details" : "Expand zone details")

                optionsMenu
            }

            if expanded {
                expandedDetail
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .move(edge: .top))
                    )
            }
        }
        .padding(MeridianSpacing.lg.rawValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(
            cornerRadius: MeridianRadius.medium.rawValue,
            tint: tintColor
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [glowColor.opacity(0.22), .clear],
                        center: .center, startRadius: 0, endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
                .offset(x: 36, y: -36)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: MeridianRadius.medium.rawValue, style: .continuous))
        // Single source of truth for the expand/collapse animation; the tap handler
        // mutates state without its own withAnimation to avoid a double-spring.
        .animation(reduceMotion ? nil : Motion.snappy(), value: expanded)
        .sheet(isPresented: $showAddContact) {
            AddContactToZoneSheet(zoneName: zone.displayName) { name in
                onAddContact(name)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: expanded)
    }

    // MARK: Header

    /// Tappable informational cluster: zone glyph, name/date/status, time, and the
    /// expand chevron. The overflow menu is a sibling (kept out of the combined a11y
    /// element so it stays independently reachable by VoiceOver).
    private var headerInfo: some View {
        HStack(alignment: .top, spacing: MeridianSpacing.md.rawValue) {
            Image(systemName: isDaylight ? "sun.max.fill" : "moon.stars.fill")
                .font(.system(size: 18))
                .foregroundStyle(isDaylight ? MeridianColors.daylightAccent : MeridianColors.nightAccent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: MeridianSpacing.xs.rawValue / 2) {
                HStack(spacing: MeridianSpacing.sm.rawValue - 2) {
                    Text(zone.displayName)
                        .font(.titleMedium)
                        .foregroundStyle(MeridianColors.onSurface)
                        .lineLimit(1)
                    if zone.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(MeridianColors.daylightAccent)
                            .accessibilityHidden(true)
                    }
                }

                Text("\(dateString) · \(utcOffsetString)")
                    .font(.bodyMedium)
                    .foregroundStyle(MeridianColors.onSurfaceVariant)

                Text(isWorkingHours ? "Working hours" : "Off hours")
                    .font(.labelMedium)
                    .foregroundStyle(
                        isWorkingHours
                            ? MeridianColors.primary.opacity(0.85)
                            : MeridianColors.onSurface.opacity(0.4)
                    )

                if !favoriteContacts.isEmpty {
                    contactPills
                        .padding(.top, MeridianSpacing.xs.rawValue)
                }
            }

            Spacer(minLength: MeridianSpacing.sm.rawValue)

            HStack(spacing: MeridianSpacing.xs.rawValue) {
                Text(timeString)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(MeridianColors.primary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MeridianColors.onSurfaceVariant.opacity(0.5))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
        }
    }

    private var contactPills: some View {
        // Horizontal wrap of starred-contact pills.
        FlowRow(spacing: MeridianSpacing.xs.rawValue) {
            ForEach(favoriteContacts) { person in
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(MeridianColors.daylightAccent)
                        .accessibilityHidden(true)
                    Text(person.name)
                        .font(.labelSmall)
                        .foregroundStyle(MeridianColors.onSurface)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background {
                    Capsule().fill(MeridianColors.secondary.opacity(0.25))
                }
            }
        }
    }

    private var optionsMenu: some View {
        Menu {
            Button {
                onToggleZoneFavorite()
            } label: {
                Label(
                    zone.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: zone.isFavorite ? "star.slash" : "star"
                )
            }
            Button {
                showAddContact = true
            } label: {
                Label("Add contact to \(zone.displayName)", systemImage: "person.badge.plus")
            }
            Button {
                onSetHome()
            } label: {
                Label("Set as My Home Zone", systemImage: "house")
            }
            Button {
                onMoveUp()
            } label: {
                Label("Move Up in Watchlist", systemImage: "arrow.up")
            }
            .disabled(isFirst)
            Button {
                onMoveDown()
            } label: {
                Label("Move Down in Watchlist", systemImage: "arrow.down")
            }
            .disabled(isLast)
            Divider()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Remove from Watchlist", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MeridianColors.onSurfaceVariant)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Zone options")
        .accessibilityHint("Favorite, add contact, reorder, or remove \(zone.displayName)")
    }

    // MARK: Expanded detail

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .overlay(MeridianColors.onSurface.opacity(0.12))
                .padding(.vertical, MeridianSpacing.md.rawValue - 2)

            HStack(alignment: .top, spacing: MeridianSpacing.xl.rawValue) {
                if let rise = sunString(sun.sunriseMinute) {
                    detailColumn(label: "Sunrise", value: rise, tint: MeridianColors.daylightAccent)
                }
                if let set = sunString(sun.sunsetMinute) {
                    detailColumn(label: "Sunset", value: set, tint: MeridianColors.nightAccent)
                }
                detailColumn(
                    label: "Work window",
                    value: String(format: "%02d:00 – %02d:00", workStartHour, workEndHour),
                    tint: MeridianColors.onSurface
                )
            }

            Text(zone.id)
                .font(.bodyMedium)
                .foregroundStyle(MeridianColors.onSurface.opacity(0.35))
                .padding(.top, MeridianSpacing.sm.rawValue - 2)
                .accessibilityLabel("Time zone identifier \(zone.id)")

            Divider()
                .overlay(MeridianColors.onSurface.opacity(0.10))
                .padding(.vertical, MeridianSpacing.md.rawValue - 2)

            contactsSection
        }
    }

    private func detailColumn(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: MeridianSpacing.xs.rawValue / 2) {
            Text(label)
                .font(.labelMedium)
                .foregroundStyle(MeridianColors.onSurface.opacity(0.5))
            Text(value)
                .font(.titleMedium)
                .foregroundStyle(tint == MeridianColors.onSurface ? MeridianColors.onSurface : tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: MeridianSpacing.sm.rawValue - 2) {
            HStack(spacing: MeridianSpacing.xs.rawValue + 2) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.5))
                    .accessibilityHidden(true)
                Text("Contacts")
                    .font(.labelMedium)
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.65))
                Spacer()
                Button {
                    showAddContact = true
                } label: {
                    Label("Add", systemImage: "person.badge.plus")
                        .font(.labelMedium)
                        .foregroundStyle(MeridianColors.primary)
                        .padding(.vertical, MeridianSpacing.sm.rawValue)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add contact to \(zone.displayName)")
            }

            if favoriteContacts.isEmpty {
                Text("No starred contacts — tap Add or star someone to include them in Plan")
                    .font(.bodyMedium)
                    .foregroundStyle(MeridianColors.onSurface.opacity(0.38))
            } else {
                ForEach(favoriteContacts) { person in
                    HStack(spacing: MeridianSpacing.xs.rawValue) {
                        Text(person.name)
                            .font(.bodyMedium)
                            .foregroundStyle(MeridianColors.onSurface)
                        Spacer(minLength: MeridianSpacing.sm.rawValue)
                        Button {
                            onToggleContactFavorite(person.id)
                        } label: {
                            Image(systemName: person.isFavorite ? "star.fill" : "star")
                                .font(.system(size: 16))
                                .foregroundStyle(
                                    person.isFavorite
                                        ? MeridianColors.daylightAccent
                                        : MeridianColors.onSurface.opacity(0.35)
                                )
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.selection, trigger: person.isFavorite)
                        .accessibilityLabel(person.isFavorite ? "Unstar \(person.name)" : "Star \(person.name)")
                        .accessibilityAddTraits(person.isFavorite ? .isSelected : [])

                        Button {
                            onRemoveContact(person.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 15))
                                .foregroundStyle(MeridianColors.error.opacity(0.85))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(person.name)")
                        .accessibilityHint("Removes this contact from \(zone.displayName)")
                    }
                }
            }
        }
    }
}

// MARK: - FlowRow (simple wrapping layout for contact pills)

/// A minimal flow layout that wraps subviews onto new lines when they overflow.
struct FlowRow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x - bounds.minX + size.width > maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("WatchlistZoneCard", traits: .sizeThatFitsLayout) {
    WatchlistZoneCard(
        zone: SavedZone(id: "Asia/Tokyo", displayName: "Tokyo", isFavorite: true),
        date: Date(),
        use24Hour: false,
        isFirst: true,
        isLast: false,
        workStartHour: 9,
        workEndHour: 17,
        contacts: [Person(name: "Aiko", tzId: "Asia/Tokyo", isFavorite: true)]
    )
    .padding()
    .background(MeridianColors.background)
    .environment(\.glassEnabled, true)
}
#endif
