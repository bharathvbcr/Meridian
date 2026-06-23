// GlassBottomSheet.swift
// Meridian — iOS 27 / Swift 6
//
// Ported from app/src/main/java/com/example/core/designsystem/GlassBottomSheet.kt
//
// Frosted-glass bottom sheet chrome matching the rest of the app. On Android this is
// a `ModalBottomSheet` with a transparent container, a 45 %-black scrim, no drag
// handle (a manual one is drawn), and a `liquidGlass` Column with a top-rounded
// 28 dp shape. On iOS the system `.sheet` provides presentation + scrim + drag
// gesture; this file supplies the glass-tinted chrome, the rounded top corners, the
// manual drag-handle affordance and the safe-area padding so the visual + behavior
// match. Sheet height matches content (`.presentationDetents([.medium, .large])` is
// applied where the content is tall; the contract default mirrors Android's
// skipPartiallyExpanded = true → a single large detent).

import SwiftUI

// MARK: - GlassBottomSheet container

/// The frosted-glass sheet body. Wrap sheet content in this to get the Meridian
/// glass chrome (rounded top, tint scrim, drag handle, safe-area padding).
struct GlassBottomSheet<Content: View>: View {

    @ViewBuilder var content: () -> Content

    @Environment(\.glassEnabled) private var glassEnabled
    @Environment(\.glassOpacity) private var glassOpacity
    @Environment(\.reduceTransparencyOverride) private var reduceTransparency

    private let shape = UnevenRoundedRectangle(
        topLeadingRadius: 28, bottomLeadingRadius: 0,
        bottomTrailingRadius: 0, topTrailingRadius: 28,
        style: .continuous
    )

    var body: some View {
        VStack(spacing: 0) {
            // Manual drag handle (Android draws its own; iOS hides the system one).
            Capsule()
                .fill(MeridianColors.onSurfaceVariant.opacity(0.4))
                .frame(width: 32, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity)

            content()
        }
        .frame(maxWidth: .infinity)
        .background {
            if reduceTransparency {
                shape.fill(MeridianColors.surface)
            } else {
                shape.fill(MeridianColors.surface.opacity(0.82))
                    .background {
                        shape.fill(glassEnabled ? AnyShapeStyle(.regularMaterial)
                                                : AnyShapeStyle(.ultraThinMaterial))
                    }
            }
        }
        .overlay {
            shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
        }
        .clipShape(shape)
        .presentationBackground(.clear)        // let the glass chrome show; system scrim stays
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - GlassFormBottomSheet

/// Form-style glass sheet with a title, scrollable body, and trailing action buttons.
struct GlassFormBottomSheet<Title: View, Content: View, Confirm: View, Dismiss: View>: View {

    @ViewBuilder var title: () -> Title
    @ViewBuilder var content: () -> Content
    @ViewBuilder var confirmButton: () -> Confirm
    @ViewBuilder var dismissButton: () -> Dismiss

    init(
        @ViewBuilder title: @escaping () -> Title,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder confirmButton: @escaping () -> Confirm,
        @ViewBuilder dismissButton: @escaping () -> Dismiss
    ) {
        self.title = title
        self.content = content
        self.confirmButton = confirmButton
        self.dismissButton = dismissButton
    }

    var body: some View {
        GlassBottomSheet {
            VStack(alignment: .leading, spacing: 0) {
                title()
                Spacer().frame(height: 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        content()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer().frame(height: 16)
                HStack {
                    Spacer()
                    dismissButton()
                    confirmButton()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }
}

// Convenience initializer for the common case with no dismiss button.
extension GlassFormBottomSheet where Dismiss == EmptyView {
    init(
        @ViewBuilder title: @escaping () -> Title,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder confirmButton: @escaping () -> Confirm
    ) {
        self.init(title: title, content: content, confirmButton: confirmButton, dismissButton: { EmptyView() })
    }
}

// MARK: - Presentation modifier

extension View {
    /// Presents `content` as a Meridian glass bottom sheet bound to `isPresented`.
    func glassBottomSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            GlassBottomSheet { content() }
        }
    }

    /// Presents a glass bottom sheet driven by an optional `Identifiable` item.
    func glassBottomSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        self.sheet(item: item) { value in
            GlassBottomSheet { content(value) }
        }
    }
}

#if DEBUG
#Preview("GlassBottomSheet") {
    ZStack {
        MeridianColors.background.ignoresSafeArea()
    }
    .glassBottomSheet(isPresented: .constant(true)) {
        VStack(alignment: .leading, spacing: 12) {
            Text("Glass sheet")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(MeridianColors.onSurface)
            Text("Frosted chrome with rounded top corners.")
                .foregroundStyle(MeridianColors.onSurfaceVariant)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .environment(\.glassOpacity, 0.6)
}
#endif
