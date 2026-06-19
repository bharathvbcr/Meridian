package com.example.feature.ai

/**
 * Heuristic check for common Markdown markers in assistant/user chat copy.
 * Plain strings skip the Markdown parser for lower overhead.
 */
internal fun looksLikeMarkdown(text: String): Boolean =
    MARKDOWN_HINT.containsMatchIn(text)

// Bold, inline code, headings, lists, blockquotes, links, and fenced code blocks.
private val MARKDOWN_HINT = Regex(
    """(\*\*.+?\*\*|__.+?__|`[^`\n]+`|^#{1,6}\s|^\s*[-*+]\s+\S|^\s*\d+\.\s+\S|^\s*>\s|]\([^)]+\)|```)""",
    RegexOption.MULTILINE,
)
