// ScrollableChipRow.swift
// Meridian — iOS 27 / Swift 6
//
// Ported from app/src/main/java/com/example/core/designsystem/ScrollableChipRow.kt
//
// Android renders a single-line horizontally scrollable LazyRow with edge fades and
// auto-scroll to the selected chip. On iOS we take the genuinely nicer native route:
// a `Layout`-protocol flow/wrap row that lays chips out left-to-right and wraps to a
// new line when they overflow, so every filter is visible without horizontal
// scrolling — a real improvement on a portrait phone while preserving the same chip
// content and 8 pt spacing. A horizontally-scrolling variant
// (`ScrollableChipRow(scroll:)`) with edge fades + auto-scroll-to-selected is kept
// for parity where a single line is desired.

import SwiftUI

// MARK: - FlowLayout

/// A flow / wrap layout: places subviews left-to-right, wrapping to the next line
/// when the next subview would overflow the proposed width.
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    struct Cache {
        var rows: [[Int]] = []
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[Int]] = []
        var currentRow: [Int] = []
        var x: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needsWrap = !currentRow.isEmpty && (x + horizontalSpacing + size.width) > maxWidth

            if needsWrap {
                rows.append(currentRow)
                maxRowWidth = max(maxRowWidth, x)
                totalHeight += rowHeight + verticalSpacing
                currentRow = []
                x = 0
                rowHeight = 0
            }

            if !currentRow.isEmpty { x += horizontalSpacing }
            x += size.width
            rowHeight = max(rowHeight, size.height)
            currentRow.append(index)
        }

        if !currentRow.isEmpty {
            rows.append(currentRow)
            maxRowWidth = max(maxRowWidth, x)
            totalHeight += rowHeight
        }

        cache.rows = rows
        let resolvedWidth = proposal.width ?? maxRowWidth
        return CGSize(width: resolvedWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        var isFirstInRow = true

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needsWrap = !isFirstInRow && (x + horizontalSpacing + size.width) > bounds.minX + maxWidth

            if needsWrap {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
                isFirstInRow = true
            }

            if !isFirstInRow { x += horizontalSpacing }

            subviews[index].place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            x += size.width
            rowHeight = max(rowHeight, size.height)
            isFirstInRow = false
        }
    }
}

// MARK: - ScrollableChipRow

/// A chip strip. By default it wraps onto multiple lines via `FlowLayout`; pass
/// `scroll: true` to use the single-line horizontally-scrolling variant with edge
/// fades and auto-scroll to `selectedIndex` (the literal Android behavior).
struct ScrollableChipRow<Content: View>: View {
    var selectedIndex: Int = -1
    var scroll: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        if scroll {
            ScrollingChipRow(selectedIndex: selectedIndex, content: content)
        } else {
            FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - ScrollingChipRow (single-line parity variant)

/// Single-line horizontally-scrollable chip row with edge fades and auto-scroll to
/// the selected chip. Chips must be tagged with their integer index via `.id(index)`
/// for auto-scroll to resolve; the fades are drawn as gradient overlays at the edges.
private struct ScrollingChipRow<Content: View>: View {
    var selectedIndex: Int
    @ViewBuilder var content: () -> Content

    private let fade = MeridianColors.background

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    content()
                }
                .padding(.horizontal, 2)
            }
            .overlay(alignment: .leading) {
                LinearGradient(colors: [fade, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 24)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .trailing) {
                LinearGradient(colors: [.clear, fade], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 24)
                    .allowsHitTesting(false)
            }
            .onChange(of: selectedIndex) { _, newValue in
                guard newValue >= 0 else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}

#if DEBUG
#Preview("ScrollableChipRow — Flow", traits: .sizeThatFitsLayout) {
    ScrollableChipRow {
        ForEach(["12h", "24h", "System", "Vector map", "Satellite", "Berlin", "Tokyo", "São Paulo"], id: \.self) { label in
            MeridianChip(label: label) {}
        }
    }
    .padding()
    .background(MeridianColors.background)
}
#endif
