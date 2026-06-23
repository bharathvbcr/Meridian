// ChatMarkdownText.swift
// Meridian — iOS 27 / Swift 6 / SwiftUI
//
// Renders assistant / user chat copy with lightweight Markdown (bold, italic,
// inline code, links, headings, bullet & ordered lists, blockquotes) while
// keeping typography compact enough for message bubbles.
//
// Behavioral port of the Android pair:
//   feature/ai/ChatMarkdown.kt      — `looksLikeMarkdown` heuristic.
//   feature/ai/ChatMarkdownText.kt  — compact mikepenz-markdown rendering.
//
// On Android the renderer is the mikepenz `Markdown` composable. iOS has no
// drop-in equivalent, so we render block structure ourselves (one `Text` per
// logical line/list-item) and use Foundation's `AttributedString(markdown:)`
// for inline spans. Plain strings skip the parser entirely (parity with
// `looksLikeMarkdown`), exactly like the Android fast-path.

import SwiftUI
import Foundation

// MARK: - Markdown heuristic (Android `looksLikeMarkdown`)

enum ChatMarkdown {

    /// Heuristic check for common Markdown markers in assistant / user chat copy.
    /// Plain strings skip the Markdown parser for lower overhead.
    ///
    /// Mirrors `ChatMarkdown.kt`'s multiline `MARKDOWN_HINT` regex:
    /// bold, inline code, headings, bullet / ordered lists, blockquotes, links,
    /// and fenced code blocks.
    static func looksLikeMarkdown(_ text: String) -> Bool {
        // NSRegularExpression with the same alternation as Android, anchored per-line
        // (`.anchorsMatchLines`) so `^#`, `^- `, `^> `, `^1. ` markers are recognised
        // mid-string.
        guard let regex = Self.hintRegex else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    /// Compiled once; the pattern is a constant so this never fails at runtime.
    // VERIFY: pattern mirrors Android MARKDOWN_HINT exactly (escaped for NSRegularExpression).
    private static let hintRegex: NSRegularExpression? = {
        let pattern =
            #"(\*\*.+?\*\*|__.+?__|`[^`\n]+`|^#{1,6}\s|^\s*[-*+]\s+\S|^\s*\d+\.\s+\S|^\s*>\s|\]\([^)]+\)|```)"#
        return try? NSRegularExpression(
            pattern: pattern,
            options: [.anchorsMatchLines]
        )
    }()
}

// MARK: - ChatMarkdownText

/// Renders chat copy with compact Markdown. When the text shows no Markdown
/// markers it is drawn as a single plain `Text` (the fast path).
struct ChatMarkdownText: View {

    let text: String
    var textColor: Color
    /// Link tint; defaults to the text color at 85 % opacity (Android default).
    var linkColor: Color

    init(text: String, textColor: Color, linkColor: Color? = nil) {
        self.text = text
        self.textColor = textColor
        self.linkColor = linkColor ?? textColor.opacity(0.85)
    }

    var body: some View {
        if ChatMarkdown.looksLikeMarkdown(text) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
            .tint(linkColor)
        } else {
            Text(text)
                .font(.bodyMedium)
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Block model

    private enum Block {
        case heading(level: Int, text: String)
        case bullet(text: String)
        case ordered(marker: String, text: String)
        case quote(text: String)
        case codeFenceLine(text: String)
        case paragraph(text: String)
    }

    /// Splits the raw markdown into logical lines and classifies each. Fenced code
    /// blocks (```) toggle a verbatim mode so their contents are not re-parsed.
    private var blocks: [Block] {
        var result: [Block] = []
        var inFence = false

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                inFence.toggle()
                continue   // Drop the fence markers themselves (parity: code shown without ```).
            }
            if inFence {
                result.append(.codeFenceLine(text: line))
                continue
            }

            if trimmed.isEmpty {
                // Preserve a blank line as an empty paragraph for spacing.
                result.append(.paragraph(text: ""))
                continue
            }

            // Headings: 1–6 leading '#'.
            if let hashEnd = trimmed.firstIndex(where: { $0 != "#" }),
               trimmed.distance(from: trimmed.startIndex, to: hashEnd) >= 1,
               trimmed.distance(from: trimmed.startIndex, to: hashEnd) <= 6,
               trimmed[hashEnd] == " " {
                let level = trimmed.distance(from: trimmed.startIndex, to: hashEnd)
                let content = String(trimmed[trimmed.index(after: hashEnd)...])
                result.append(.heading(level: level, text: content))
                continue
            }

            // Blockquote: '> '.
            if trimmed.hasPrefix(">") {
                let content = String(trimmed.drop(while: { $0 == ">" })).trimmingCharacters(in: .whitespaces)
                result.append(.quote(text: content))
                continue
            }

            // Bullet list: '-', '*' or '+' followed by whitespace.
            if let first = trimmed.first, "-*+".contains(first),
               trimmed.count >= 2, trimmed[trimmed.index(after: trimmed.startIndex)] == " " {
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                result.append(.bullet(text: content))
                continue
            }

            // Ordered list: digits followed by '. '.
            if let dotIndex = trimmed.firstIndex(of: "."),
               dotIndex > trimmed.startIndex,
               trimmed[trimmed.startIndex..<dotIndex].allSatisfy(\.isNumber),
               trimmed.index(after: dotIndex) < trimmed.endIndex,
               trimmed[trimmed.index(after: dotIndex)] == " " {
                let marker = String(trimmed[trimmed.startIndex...dotIndex])
                let content = String(trimmed[trimmed.index(dotIndex, offsetBy: 2)...])
                result.append(.ordered(marker: marker, text: content))
                continue
            }

            result.append(.paragraph(text: line))
        }
        return result
    }

    // MARK: Block rendering

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case let .heading(level, content):
            inlineText(content)
                .font(.system(size: 14, weight: headingWeight(level)))
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)

        case let .bullet(content):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .font(.bodyMedium)
                    .foregroundStyle(textColor.opacity(0.7))
                inlineText(content)
                    .font(.bodyMedium)
                    .foregroundStyle(textColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case let .ordered(marker, content):
            HStack(alignment: .top, spacing: 6) {
                Text(marker)
                    .font(.bodyMedium)
                    .foregroundStyle(textColor.opacity(0.7))
                    .monospacedDigit()
                inlineText(content)
                    .font(.bodyMedium)
                    .foregroundStyle(textColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case let .quote(content):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(textColor.opacity(0.3))
                    .frame(width: 3)
                inlineText(content)
                    .font(.bodyMedium.italic())
                    .foregroundStyle(textColor.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 2)

        case let .codeFenceLine(content):
            Text(content.isEmpty ? " " : content)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(textColor.opacity(0.12))
                }

        case let .paragraph(content):
            if content.isEmpty {
                // Blank-line spacer.
                Color.clear.frame(height: 4)
            } else {
                inlineText(content)
                    .font(.bodyMedium)
                    .foregroundStyle(textColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func headingWeight(_ level: Int) -> Font.Weight {
        switch level {
        case 1, 2: return .bold
        case 3, 4: return .semibold
        default:   return .medium
        }
    }

    // MARK: Inline markdown

    /// Renders inline markdown (bold, italic, inline code, links) via Foundation's
    /// `AttributedString(markdown:)`. `.inlineOnlyPreservingWhitespace` keeps the
    /// run on one logical line (we already split blocks ourselves), so list markers
    /// and headings the parser would otherwise swallow are handled above.
    private func inlineText(_ markdown: String) -> Text {
        // VERIFY: AttributedString(markdown:options:) + InlineOnlyPreservingWhitespace
        // is available since iOS 15 — stable on iOS 27.
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return Text(attributed)
        }
        return Text(markdown)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("ChatMarkdownText", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: 16) {
        ChatMarkdownText(
            text: "Plain text with **bold**, *italic*, and `code` plus a [link](https://example.com).",
            textColor: Color(hex: "#F1F5F9")
        )
        ChatMarkdownText(
            text: """
            ## Best meeting window
            - **New York**: 9 AM–11 AM
            - **London**: 2 PM–4 PM
            1. Open the Plan screen
            2. Pick the optimal slot

            > Tip: rotate the time weekly for fairness.
            """,
            textColor: Color(hex: "#F1F5F9"),
            linkColor: Color(hex: "#60CDFF")
        )
    }
    .padding()
    .background(Color(hex: "#020617"))
}
#endif
