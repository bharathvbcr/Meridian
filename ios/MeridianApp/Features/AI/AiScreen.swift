// AiScreen.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// AI Assistant screen, wired to the SHARED `MainViewModel` (chatMessages /
// aiLoading / pendingDraft / sendAiMessage / confirmDraft / discardDraft /
// clearChat). Behavioral port of feature/ai/AiScreen.kt:
//
//   • collapsible QuickScheduleCard (model-free scheduling)
//   • "Try asking" prompt-starter chips
//   • grounding-aware conversation rendered with compact Markdown
//   • @Generable draft → DraftConfirmCard propose / confirm / discard flow (§12.8)
//   • per-message inference-source badge (On-Device / Cloud)
//   • typing indicator, copy-to-clipboard + haptics, auto-scroll, jump-to-latest
//   • active engine pill in the header sourced from `settings.aiEngine`
//
// The assistant never computes timestamps and never auto-writes a task — all
// scheduling routes through the MainViewModel draft-confirm flow.

import SwiftUI

// MARK: - Suggestions (Android `SUGGESTIONS`)

private let kAiSuggestions = [
    "What time is it in Tokyo right now?",
    "Schedule a call with London next Monday at 2 PM",
    "Best meeting time for New York, Berlin, and Singapore?",
    "Convert 9 AM Sydney time to my local time",
]

// MARK: - Local layout constants / helpers

/// Minimum comfortable hit target on iOS (Apple HIG). Kept private to this file
/// so the shared design system is untouched; mirrors the 48dp Android minimum.
private let kMinTapTarget: CGFloat = 44

/// Bottom clearance for the conversation list so the last message clears the
/// pinned composer + floating tab bar. Derived name instead of a bare magic
/// number so it tracks the composer inset intent.
private let kConversationBottomInset: CGFloat = 120

// MARK: - PressableButtonStyle

/// Shared press feedback matching `GlassNavBar`'s `NavPressStyle` (scale +
/// `Motion.quick()`), so every plain button in this screen feels physical and
/// consistent with the rest of the app. Honors Reduce Motion.
private struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(reduceMotion ? nil : Motion.quick(), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

// MARK: - AiScreen

struct AiScreen: View {

    @Environment(\.mainViewModel) private var injectedViewModel

    var body: some View {
        if let viewModel = injectedViewModel {
            AiScreenContent(viewModel: viewModel)
        } else {
            // Should never happen in-app (the root injects the VM); keep a safe fallback.
            ContentUnavailableView(
                "Assistant unavailable",
                systemImage: "sparkles",
                description: Text("The assistant could not be initialised.")
            )
            .background(MeridianColors.background.ignoresSafeArea())
        }
    }
}

// MARK: - AiScreenContent

private struct AiScreenContent: View {

    @Bindable var viewModel: MainViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var inputText = ""
    @State private var clearTrigger = 0
    @State private var sendTrigger = 0
    @State private var nearBottom = true

    private var is24Hour: Bool {
        TimeFormats.uses24Hour(cycle: viewModel.settings.hourCycle)
    }

    private var savedZonePairs: [(id: String, displayName: String)] {
        viewModel.savedZones.map { ($0.id, $0.displayName) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            MeridianColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                AssistantHeader(
                    engine: viewModel.settings.aiEngine,
                    canClear: viewModel.chatMessages.count > 1,
                    onClear: {
                        clearTrigger &+= 1
                        withAnimation(reduceMotion ? nil : Motion.snappy()) {
                            viewModel.clearChat()
                        }
                    }
                )

                conversationList
            }
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: clearTrigger)
        .sensoryFeedback(.selection, trigger: sendTrigger)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChatComposer(text: $inputText) { send(inputText) }
        }
    }

    // MARK: Conversation list

    private var conversationList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MeridianSpacing.md.rawValue) {
                    Color.clear
                        .frame(height: 0)
                        .reportScrollOffset(in: "aiScroll")

                    // Quick scheduler — model is never involved.
                    QuickScheduleCard(
                        savedZones: savedZonePairs,
                        is24Hour: is24Hour,
                        searchZones: { await viewModel.searchTimeZones($0) },
                        onAdd: { viewModel.addTask($0) }
                    )

                    // Prompt starters.
                    SectionHeader(title: "TRY ASKING")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: MeridianSpacing.sm.rawValue) {
                            ForEach(kAiSuggestions, id: \.self) { prompt in
                                Button { send(prompt) } label: {
                                    Text(prompt)
                                        .font(.labelMedium)
                                        .foregroundStyle(MeridianColors.onSurface)
                                        .padding(.horizontal, 14)
                                        .frame(minHeight: kMinTapTarget)
                                        .background {
                                            Capsule()
                                                .fill(MeridianColors.surface.opacity(0.6))
                                                .overlay {
                                                    Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                                                }
                                        }
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.pressable)
                                .accessibilityHint("Sends this prompt to the assistant")
                            }
                        }
                        // Small vertical breathing room so the taller chips don't clip.
                        .padding(.vertical, MeridianSpacing.xs.rawValue)
                    }

                    // First-run leads with Quick schedule + prompt starters; the
                    // CONVERSATION section only appears once there's a real exchange
                    // beyond the seed greeting.
                    if viewModel.chatMessages.count > 1 {
                        SectionHeader(title: "CONVERSATION")
                    }

                    ForEach(viewModel.chatMessages) { message in
                        MessageBubble(
                            message: message,
                            onRetry: message.isError ? { viewModel.retryAiMessage(errorMessageId: message.id) } : nil
                        )
                            .id(message.id)
                    }

                    if viewModel.aiLoading {
                        if let partial = viewModel.aiPartialText {
                            StreamingPartialBubble(text: partial)
                                .id("streaming")
                        } else {
                            TypingIndicator()
                                .id("typing")
                        }
                    }

                    if let draft = viewModel.pendingDraft {
                        DraftConfirmCard(
                            draft: draft,
                            is24Hour: is24Hour,
                            onConfirm: { viewModel.confirmDraft() },
                            onDiscard: { viewModel.discardDraft() }
                        )
                        .id("draft_confirm")
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, MeridianSpacing.lg.rawValue)
                .padding(.top, MeridianSpacing.md.rawValue)
                .padding(.bottom, kConversationBottomInset)
            }
            .coordinateSpace(name: "aiScroll")
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height
                    >= geometry.contentSize.height - 160
            } action: { _, isNearBottom in
                nearBottom = isNearBottom
            }
            .onChange(of: viewModel.chatMessages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: viewModel.aiLoading) { _, _ in scrollToBottom(proxy) }
            .onChange(of: viewModel.aiPartialText) { _, _ in scrollToBottom(proxy) }
            .onChange(of: viewModel.pendingDraft?.id) { _, _ in scrollToBottom(proxy) }
            // Jump-to-latest when the user has scrolled up (Android: FilledTonalIconButton
            // shown while listState.canScrollForward).
            .overlay(alignment: .bottomTrailing) {
                if !nearBottom {
                    Button { scrollToBottom(proxy) } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(MeridianColors.primary)
                            .frame(width: kMinTapTarget, height: kMinTapTarget)
                            .background {
                                Circle()
                                    .fill(MeridianColors.primaryContainer)
                                    .overlay {
                                        Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                                    }
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.pressable)
                    .padding(.trailing, MeridianSpacing.lg.rawValue)
                    .padding(.bottom, MeridianSpacing.md.rawValue)
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                    .accessibilityLabel("Jump to latest")
                    .accessibilityHint("Scrolls to the newest message")
                }
            }
            .animation(reduceMotion ? nil : Motion.snappy(), value: nearBottom)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : Motion.smooth()) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    // MARK: Send

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sendTrigger &+= 1
        inputText = ""
        Task { await viewModel.sendAiMessage(trimmed) }
    }
}

// MARK: - AssistantHeader

private struct AssistantHeader: View {
    let engine: AiEngine
    let canClear: Bool
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: MeridianSpacing.md.rawValue) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [MeridianColors.primary, MeridianColors.nightAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MeridianColors.onPrimary)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Meridian Assistant")
                    .font(.titleLarge)
                    .foregroundStyle(MeridianColors.onBackground)
                EngineLabel(engine: engine)
            }
            .accessibilityElement(children: .combine)

            Spacer()

            if canClear {
                Button(action: onClear) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                        .frame(width: kMinTapTarget, height: kMinTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .transition(.opacity)
                .accessibilityLabel("Clear conversation")
                .accessibilityHint("Deletes all messages and starts a new chat")
            }
        }
        .padding(.horizontal, MeridianSpacing.lg.rawValue)
        .padding(.vertical, MeridianSpacing.md.rawValue)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.6))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                }
                .ignoresSafeArea(edges: .top)
        }
    }
}

// MARK: - EngineLabel (active engine per settings.aiEngine)

private struct EngineLabel: View {
    let engine: AiEngine

    var body: some View {
        Label(
            engine == .onDevice ? "On-Device" : "Cloud",
            systemImage: engine == .onDevice ? "cpu" : "cloud"
        )
        .font(.labelMedium)
        .foregroundStyle(engine == .onDevice ? MeridianColors.primary : MeridianColors.onSurfaceVariant)
        .accessibilityLabel(engine == .onDevice ? "Active engine, on device" : "Active engine, cloud")
    }
}

// MARK: - MessageBubble

private struct MessageBubble: View {
    let message: ChatMessage
    var onRetry: (() -> Void)? = nil

    @State private var copyTrigger = 0
    /// Bubble width cap that scales with Dynamic Type instead of the old
    /// hardcoded 300pt literal — at larger text sizes wrapped copy needs more
    /// room, so the cap grows with the user's chosen body size rather than
    /// clipping. The leading/trailing `Spacer(minLength: 40)` gutters keep it
    /// from overflowing narrow devices even as the cap grows.
    @ScaledMetric(relativeTo: .body) private var scaledBubbleCap: CGFloat = 300

    private var isUser: Bool { message.isUser }

    /// Spoken as a single phrase with sender context so VoiceOver doesn't read
    /// the avatar glyph, text, and badge as three unlabelled swipes.
    private var accessibilityText: String {
        let source = message.source.map { badgeLabel(for: $0) }
        if isUser {
            return "You said: \(message.text)"
        } else if message.isError {
            return "Assistant error: \(message.text)"
        } else if let source {
            return "Assistant, \(source): \(message.text)"
        } else {
            return "Assistant: \(message.text)"
        }
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: MeridianSpacing.xs.rawValue) {
            HStack(alignment: .bottom, spacing: MeridianSpacing.sm.rawValue) {
                if isUser { Spacer(minLength: 40) }

                if !isUser {
                    ZStack {
                        Circle()
                            .fill((message.isError ? MeridianColors.error : MeridianColors.primary).opacity(0.15))
                            .frame(width: 28, height: 28)
                        Image(systemName: message.isError ? "exclamationmark.triangle" : "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(message.isError ? MeridianColors.error : MeridianColors.primary)
                    }
                    .accessibilityHidden(true)
                }

                bubbleBody
                    .frame(maxWidth: scaledBubbleCap, alignment: isUser ? .trailing : .leading)

                if !isUser { Spacer(minLength: 40) }
            }

            // Provenance badge for assistant replies that recorded an inference source.
            if !isUser, let source = message.source {
                InferenceSourceBadge(source: source)
                    .padding(.leading, 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .sensoryFeedback(.impact(weight: .light), trigger: copyTrigger)
        // Group the avatar / bubble / badge into one swipe with a sender-prefixed
        // phrase, then re-expose the interactive actions (which .combine would
        // otherwise flatten) via the actions rotor.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAction(named: "Copy") {
            UIPasteboard.general.string = message.text
            copyTrigger &+= 1
        }
        .modifier(RetryAccessibilityAction(onRetry: message.isError ? onRetry : nil))
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.text
                copyTrigger &+= 1
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }

    @ViewBuilder
    private var bubbleBody: some View {
        if isUser {
            Text(message.text)
                .font(.bodyLarge)
                .foregroundStyle(MeridianColors.onPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(MeridianColors.primary)
                }
        } else if message.isError {
            // Failed turn: error-container bubble, plain text (no markdown) —
            // Android renders `sender == "System Error"` the same way.
            VStack(alignment: .leading, spacing: MeridianSpacing.sm.rawValue) {
                Text(message.text)
                    .font(.bodyLarge)
                    .foregroundStyle(MeridianColors.onErrorContainer)
                if let onRetry {
                    Button(action: onRetry) {
                        Label("Try again", systemImage: "arrow.clockwise")
                            .font(.labelMedium)
                            .foregroundStyle(MeridianColors.error)
                            .frame(minHeight: kMinTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Try again")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(MeridianColors.errorContainer.opacity(0.55))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(MeridianColors.error.opacity(0.35), lineWidth: 1)
                    }
            }
        } else {
            ChatMarkdownText(
                text: message.text,
                textColor: MeridianColors.onSurface,
                linkColor: MeridianColors.primary
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Shared glass treatment — reads the glass + reduceTransparency
            // environment so assistant bubbles read identically to
            // DraftConfirmCard/QuickScheduleCard and degrade opaquely when
            // Reduce Transparency is on (the old material block ignored it).
            .liquidGlass(cornerRadius: 18)
        }
    }
}

// MARK: - RetryAccessibilityAction

/// Adds a "Try again" custom accessibility action only when a retry handler is
/// present. Because `MessageBubble` groups its children with `.combine`, the
/// visible retry button would otherwise lose its VoiceOver action; this rotor
/// action restores it.
private struct RetryAccessibilityAction: ViewModifier {
    let onRetry: (() -> Void)?

    func body(content: Content) -> some View {
        if let onRetry {
            content.accessibilityAction(named: "Try again") { onRetry() }
        } else {
            content
        }
    }
}

// MARK: - InferenceSourceBadge

/// Truthful, human-readable provenance label shared by the badge and the
/// message-bubble VoiceOver phrase, so both stay in sync.
private func badgeLabel(for source: InferenceSource) -> String {
    switch source {
    case .onDevice: "On-Device"
    case .cloud: "Cloud"
    case .rules: "On-device · Rules"
    case .cached: "Instant · Cached"
    }
}

/// Truthful provenance pill. Three distinct sources: the deterministic rules
/// fallback is local/offline, so it must never render as "Cloud" (that would be
/// a false privacy signal).
private struct InferenceSourceBadge: View {
    let source: InferenceSource

    private var label: String { badgeLabel(for: source) }

    private var icon: String {
        switch source {
        case .cloud: "cloud"
        case .cached: "bolt.fill"
        default: "cpu"
        }
    }

    /// Local sources get the primary (privacy-positive) tint; cloud stays neutral.
    private var isLocal: Bool { source != .cloud }

    var body: some View {
        HStack(spacing: MeridianSpacing.xs.rawValue) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(isLocal ? MeridianColors.primary : MeridianColors.onSurfaceVariant)
        .padding(.horizontal, MeridianSpacing.sm.rawValue)
        .padding(.vertical, 3)
        .background {
            Capsule()
                .fill(isLocal ? MeridianColors.primary.opacity(0.12) : MeridianColors.surface.opacity(0.8))
                .overlay {
                    Capsule().strokeBorder(
                        isLocal ? MeridianColors.primary.opacity(0.3) : Color.white.opacity(0.1),
                        lineWidth: 1
                    )
                }
        }
        // Speak "On-device · Rules" as one phrase, not a 'cpu' image plus text.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Answered by \(label)")
    }
}

// MARK: - StreamingPartialBubble

private struct StreamingPartialBubble: View {
    let text: String

    var body: some View {
        HStack(alignment: .bottom, spacing: MeridianSpacing.sm.rawValue) {
            ZStack {
                Circle()
                    .fill(MeridianColors.primary.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MeridianColors.primary)
            }
            .accessibilityHidden(true)

            ChatMarkdownText(text: text, textColor: MeridianColors.onSurface)
                .padding(.horizontal, MeridianSpacing.md.rawValue)
                .padding(.vertical, MeridianSpacing.sm.rawValue)
                .background {
                    RoundedRectangle(cornerRadius: MeridianRadius.lg.rawValue, style: .continuous)
                        .fill(MeridianColors.surfaceVariant.opacity(0.35))
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Assistant is responding")
    }
}

// MARK: - TypingIndicator

private struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    var body: some View {
        HStack(alignment: .bottom, spacing: MeridianSpacing.sm.rawValue) {
            ZStack {
                Circle()
                    .fill(MeridianColors.primary.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MeridianColors.primary)
            }
            .accessibilityHidden(true)

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(MeridianColors.onSurfaceVariant)
                        .frame(width: 8, height: 8)
                        // Static, evenly-dimmed dots under Reduce Motion — no
                        // perpetual repeatForever pulse for those users.
                        .opacity(reduceMotion ? 0.6 : (animating ? 1.0 : 0.3))
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: 0.6)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.15),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, MeridianSpacing.lg.rawValue)
            .padding(.vertical, 14)
            // Shared glass surface so the typing bubble matches assistant replies.
            .liquidGlass(cornerRadius: 16, tintOpacity: 0)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Assistant is typing")
        .accessibilityAddTraits(.updatesFrequently)
        .onAppear { if !reduceMotion { animating = true } }
    }
}

// MARK: - ChatComposer

private struct ChatComposer: View {
    @Binding var text: String
    let onSend: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: MeridianSpacing.md.rawValue) {
            HStack(spacing: MeridianSpacing.sm.rawValue) {
                TextField(
                    "Ask anything — time zones, best meeting windows, schedule…",
                    text: $text,
                    axis: .vertical
                )
                .font(.bodyLarge)
                .foregroundStyle(MeridianColors.onSurface)
                .tint(MeridianColors.primary)
                .lineLimit(1...5)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { if canSend { onSend() } }
                .accessibilityLabel("Message the assistant")

                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(MeridianColors.onSurfaceVariant)
                            // 44pt hit area without forcing the field taller:
                            // an expanded content shape, not a hard frame.
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                    .accessibilityLabel("Clear text")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            // Shared glass surface; focus is signalled by a primary tint wash.
            // Honors Reduce Transparency via the same modifier the rest of the
            // app uses (the old .ultraThinMaterial block ignored it).
            .liquidGlass(
                cornerRadius: 22,
                tint: MeridianColors.primary,
                tintOpacity: focused ? 0.12 : 0,
                borderWidth: 1
            )
            .animation(reduceMotion ? nil : Motion.snappy(), value: focused)

            Button {
                if canSend { onSend() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    // Dim the glyph too when disabled so enabled vs disabled is
                    // unmistakable — the arrow no longer floats on a washed circle.
                    .foregroundStyle(canSend ? MeridianColors.onPrimary : MeridianColors.onSurfaceVariant)
                    .frame(width: kMinTapTarget, height: kMinTapTarget)
                    .background {
                        Circle().fill(canSend ? MeridianColors.primary : MeridianColors.surface.opacity(0.8))
                    }
                    .overlay {
                        if !canSend {
                            Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        }
                    }
            }
            .buttonStyle(.pressable)
            .disabled(!canSend)
            .animation(reduceMotion ? nil : Motion.snappy(), value: canSend)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, MeridianSpacing.lg.rawValue)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.85))
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
        // No fixed tab-bar clearance here: ContentView reserves space for the floating glass tab
        // bar via `.safeAreaInset(.bottom)`, which this composer (pinned through the screen's own
        // safeAreaInset) already sits above. A fixed 84pt on top of that double-counted and floated
        // the composer mid-screen; the screen's own inset keeps it snug above the keyboard while editing.
    }
}

// MARK: - Preview

#if DEBUG
import SwiftData

#Preview("AiScreen") {
    let container = try! ModelContainer(
        for: SavedZone.self, Person.self, PlannedTask.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let viewModel = MainViewModel(modelContext: container.mainContext)
    return AiScreen()
        .modelContainer(container)
        .meridianEnvironment(viewModel: viewModel, settings: SettingsRepository.shared.settings)
        .preferredColorScheme(.dark)
}
#endif
