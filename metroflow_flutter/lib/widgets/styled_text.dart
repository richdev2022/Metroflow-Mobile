import 'package:flutter/material.dart';

/// Parsed span kinds for WhatsApp-style inline styling.
enum _SpanKind { plain, bold, italic, strike, code }

class _ParsedSpan {
  final _SpanKind kind;
  final String text;
  const _ParsedSpan(this.kind, this.text);
}

/// Parses a chat message body into styled spans, matching the web renderer:
///
///   *bold*        _italic_        ~strikethrough~        `monospace`
///
/// Markers must wrap non-empty content that does not start with a space, and
/// (like WhatsApp) bold/italic/strike cannot cross a newline; `code` may.
List<_ParsedSpan> _parse(String input) {
  final spans = <_ParsedSpan>[];

  void parseStyled(String src) {
    final buffer = StringBuffer();
    var i = 0;
    void flush() {
      if (buffer.isNotEmpty) {
        spans.add(_ParsedSpan(_SpanKind.plain, buffer.toString()));
        buffer.clear();
      }
    }

    while (i < src.length) {
      final c = src[i];
      _SpanKind? kind;
      if (c == '*') kind = _SpanKind.bold;
      if (c == '_') kind = _SpanKind.italic;
      if (c == '~') kind = _SpanKind.strike;
      final opens = kind != null &&
          i + 1 < src.length &&
          src[i + 1] != ' ' &&
          src[i + 1] != c;

      if (opens) {
        var close = -1;
        for (var j = i + 1; j < src.length; j++) {
          if (src[j] == '\n') break; // markers stay within one line
          if (src[j] == c && src[j - 1] != ' ') {
            close = j;
            break;
          }
        }
        if (close > i + 1) {
          flush();
          spans.add(_ParsedSpan(kind, src.substring(i + 1, close)));
          i = close + 1;
          continue;
        }
      }
      buffer.write(c);
      i++;
    }
    flush();
  }

  // Code spans first — no other styling inside them.
  final codeRe = RegExp('`([^`\n]+)`');
  var last = 0;
  for (final m in codeRe.allMatches(input)) {
    if (m.start > last) parseStyled(input.substring(last, m.start));
    spans.add(_ParsedSpan(_SpanKind.code, m.group(1)!));
    last = m.end;
  }
  if (last < input.length) parseStyled(input.substring(last));
  return spans;
}

/// Rich-text message body with WhatsApp-style `*bold*` / `_italic_` /
/// `~strike~` / backtick-code support. Plain-looking (falls back to a plain
/// Text) when the message contains no markers at all.
class StyledText extends StatelessWidget {
  final String text;
  final TextStyle? baseStyle;
  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign textAlign;

  const StyledText(
    this.text, {
    super.key,
    this.baseStyle,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.textAlign = TextAlign.start,
  });

  bool get _hasMarkers =>
      text.contains('*') || text.contains('_') || text.contains('~') || text.contains('`');

  @override
  Widget build(BuildContext context) {
    final base = baseStyle ?? DefaultTextStyle.of(context).style;
    if (!_hasMarkers) {
      return Text(
        text,
        style: base,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      );
    }

    final spans = <InlineSpan>[];
    for (final span in _parse(text)) {
      TextStyle? style;
      switch (span.kind) {
        case _SpanKind.bold:
          style = base.copyWith(fontWeight: FontWeight.w700);
          break;
        case _SpanKind.italic:
          style = base.copyWith(fontStyle: FontStyle.italic);
          break;
        case _SpanKind.strike:
          style = base.copyWith(decoration: TextDecoration.lineThrough);
          break;
        case _SpanKind.code:
          style = base.copyWith(
            fontFamily: 'monospace',
            fontSize: base.fontSize != null ? base.fontSize! * 0.92 : null,
            backgroundColor:
                base.color?.withValues(alpha: 0.14) ?? Colors.black.withValues(alpha: 0.08),
          );
          break;
        case _SpanKind.plain:
          style = null;
          break;
      }
      spans.add(TextSpan(text: span.text, style: style));
    }

    return Text.rich(
      TextSpan(children: spans),
      style: base,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
}
