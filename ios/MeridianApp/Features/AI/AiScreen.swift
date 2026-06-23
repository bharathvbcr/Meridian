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

    @State private var inputText = ""
    @State private var clearTrigger = 0

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
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            viewModel.clearChat()
                        }
                    }
                )

                conversationList
            }
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: clearTrigger)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ChatComposer(text: $inputText) { send(inputText) }
        }
    }

    // MARK: Conversation list

    private var conversationList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
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
                        HStack(spacing: 8) {
                            ForEach(kAiSuggestions, id: \.self) { prompt in
                                Button { send(prompt) } label: {
                                    Text(prompt)
                                        .font(.labelMedium)
                                        .foregroundStyle(MeridianColors.onSurface)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background {
                                            Capsule()
                                                .fill(MeridianColors.surface.opacity(0.6))
                                                .overlay {
                                                    Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                                                }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    SectionHeader(title: "CONVERSATION")

                    ForEach(viewModel.chatMessages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if viewModel.aiLoading {
                        TypingIndicator()
                            .id("typing")
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
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.chatMessages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: viewModel.aiLoading) { _, _ in scrollToBottom(proxy) }
            .onChange(of: viewModel.pendingDraft?.id) { _, _ in scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    // MARK: Send

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
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
        HStack(spacing: 12) {
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

            VStack(alignment: .leading, spacing: 2) {
                Text("Meridian Assistant")
                    .font(.titleLarge)
                    .foregroundStyle(MeridianColors.onBackground)
                EngineLabel(engine: engine)
            }

            Spacer()

            if canClear {
                Button(action: onClear) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(MeridianColors.onSurfaceVariant)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
    }
}

// MARK: - MessageBubble

private struct MessageBubble: View {
    let message: ChatMessage

    @State private var copyTrigger = 0

    private var isUser: Bool { message.isUser }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 8) {
                if isUser { Spacer(minLength: 40) }

                if !isUser {
                    ZStack {
                        Circle()
                            .fill(MeridianColors.primary.opacity(0.15))
                            .frame(width: 28, height: 28)
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MeridianColors.primary)
                    }
                }

                bubbleBody
                    .frame(maxWidth: 300, alignment: isUser ? .trailing : .leading)

                if !isUser { Spacer(minLength: 40) }
            }

            // Provenance badge for assistant replies that recorded an inference source.
            if !isUser, let onDevice = message.onDevice {
                InferenceSourceBadge(onDevice: onDevice)
                    .padding(.leading, 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .sensoryFeedback(.impact(weight: .light), trigger: copyTrigger)
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
        } else {
            ChatMarkdownText(
                text: message.text,
                textColor: MeridianColors.onSurface,
                linkColor: MeridianColors.primary
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(MeridianColors.primary.opacity(0.06))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    }
            }
        }
    }
}

// MARK: - InferenceSourceBadge (On-Device / Cloud — relabels the old wrong "Rule-Based"/"Cloud Gemini")

private struct InferenceSourceBadge: View {
    let onDevice: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: onDevice ? "cpu" : "cloud")
                .font(.system(size: 9, weight: .semibold))
            Text(onDevice ? "On-Device" : "Cloud")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(onDevice ? MeridianColors.primary : MeridianColors.onSurfaceVariant)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background {
            Capsule()
                .fill(onDevice ? MeridianColors.primary.opacity(0.12) : MeridianColors.surface.opacity(0.8))
                .overlay {
                    Capsule().strokeBorder(
                        onDevice ? MeridianColors.primary.opacity(0.3) : Color.white.opacity(0.1),
                        lineWidth: 1
                    )
                }
        }
    }
}

// MARK: - TypingIndicator

private struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack {
                Circle()
                    .fill(MeridianColors.primary.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MeridianColors.primary)
            }

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(MeridianColors.onSurfaceVariant)
                        .frame(width: 8, height: 8)
                        .opacity(animating ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.15),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { animating = true }
    }
}

// MARK: - ChatComposer

private struct ChatComposer: View {
    @Binding var text: String
    let onSend: () -> Void

    @FocusState private var focused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
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

                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(MeridianColors.onSurfaceVariant)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                focused ? MeridianColors.primary.opacity(0.5) : Color.white.opacity(0.2),
                                lineWidth: 1
                            )
                    }
            }
            .animation(.easeInOut(duration: 0.2), value: focused)

            Button {
                if canSend { onSend() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(MeridianColors.onPrimary)
                    .frame(width: 44, height: 44)
                    .background {
                        Circle().fill(MeridianColors.primary.opacity(canSend ? 1.0 : 0.4))
                    }
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .animation(.easeInOut(duration: 0.15), value: canSend)
        }
        .padding(.horizontal, 16)
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
        // Clearance above the floating glass tab bar (≈72pt pill + 16pt inset) when the
        // keyboard is down; collapses to 0 while editing so the bar rides snug above the IME.
        .padding(.bottom, focused ? 0 : 84)
        .animation(.easeInOut(duration: 0.2), value: focused)
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
