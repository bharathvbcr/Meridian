package com.example.feature.ai

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.mikepenz.markdown.compose.Markdown
import com.mikepenz.markdown.m3.markdownColor
import com.mikepenz.markdown.m3.markdownTypography
import com.mikepenz.markdown.model.markdownAnimations
import com.mikepenz.markdown.model.markdownPadding

/**
 * Renders assistant/user chat copy with Markdown (bold, italic, lists, links, code, etc.)
 * while keeping typography compact enough for message bubbles.
 */
@Composable
fun ChatMarkdownText(
    text: String,
    textColor: Color,
    modifier: Modifier = Modifier,
    linkColor: Color = textColor.copy(alpha = 0.85f),
) {
    val body = MaterialTheme.typography.bodyMedium
    if (!looksLikeMarkdown(text)) {
        Text(
            text = text,
            color = textColor,
            style = body,
            modifier = modifier,
        )
        return
    }

    Markdown(
        content = text,
        modifier = modifier,
        colors = chatMarkdownColors(textColor = textColor),
        typography = chatMarkdownTypography(body = body, linkColor = linkColor),
        padding = chatMarkdownPadding(),
        immediate = true,
        retainState = true,
        animations = markdownAnimations(animateTextSize = { this }),
    )
}

@Composable
private fun chatMarkdownColors(textColor: Color) = markdownColor(
    text = textColor,
    codeBackground = textColor.copy(alpha = 0.12f),
    inlineCodeBackground = textColor.copy(alpha = 0.12f),
    dividerColor = textColor.copy(alpha = 0.2f),
    tableBackground = textColor.copy(alpha = 0.06f),
)

@Composable
private fun chatMarkdownTypography(body: TextStyle, linkColor: Color) = markdownTypography(
    h1 = body.copy(fontWeight = FontWeight.Bold),
    h2 = body.copy(fontWeight = FontWeight.Bold),
    h3 = body.copy(fontWeight = FontWeight.SemiBold),
    h4 = body.copy(fontWeight = FontWeight.SemiBold),
    h5 = body.copy(fontWeight = FontWeight.Medium),
    h6 = body.copy(fontWeight = FontWeight.Medium),
    text = body,
    paragraph = body,
    ordered = body,
    bullet = body,
    list = body,
    quote = body.copy(fontStyle = FontStyle.Italic),
    code = body.copy(fontFamily = FontFamily.Monospace),
    inlineCode = body.copy(fontFamily = FontFamily.Monospace),
    textLink = TextLinkStyles(
        style = body.copy(
            color = linkColor,
            fontWeight = FontWeight.Medium,
            textDecoration = TextDecoration.Underline,
        ).toSpanStyle(),
    ),
)

@Composable
private fun chatMarkdownPadding() = markdownPadding(
    block = 0.dp,
    list = 2.dp,
    listItemTop = 1.dp,
    listItemBottom = 1.dp,
    listIndent = 6.dp,
    codeBlock = PaddingValues(horizontal = 8.dp, vertical = 4.dp),
    blockQuote = PaddingValues(horizontal = 8.dp),
    blockQuoteText = PaddingValues(vertical = 2.dp),
)
