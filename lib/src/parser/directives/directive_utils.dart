part of 'directives.dart';

/// Skips to the next non-empty directive line.
///
/// Returns `true` only if the current character is a [directive] (`%`)
/// indicator. Returns `false` only if:
///   - No more characters are present
///   - No line breaks were skipped
///   - The next character looks like a [directiveEndSingle] (`-`)
///
/// Otherwise, always throws since the conditions above all failed when a
/// non-zero positive indent was encountered.
bool _skipToNextNonEmptyLine(
  SourceIterator iterator,
  void Function(YamlComment comment) onParseComment,
) {
  bool canSkip() => !iterator.isEOF && iterator.current.isLineBreak();

  skipper:
  do {
    final indent = skipToParsableChar(iterator, onParseComment: onParseComment);

    // Let [parseDirectives] handle this
    if (indent == null) return false;

    switch (iterator.current) {
      // End parsing
      case directiveEndSingle when indent == 0:
        return false;

      // Next directive
      case directive when indent == 0:
        return true;

      // Attempt to salvage the current line. This may be an empty line.
      case tab:
        {
          skipWhitespace(iterator, skipTabs: true);
          iterator.nextChar();

          if (canSkip()) continue skipper;

          continue throwable;
        }

      throwable:
      default:
        {
          // Nothing else. Let top level parser handle this.
          if (iterator.isEOF) {
            break skipper;
          }

          throwForCurrentLine(
            iterator,
            message:
                'Expected a non-indented directive line with directives or a '
                'directive end marker',
            end: iterator.currentLineInfo.current,
          );
        }
    }
  } while (canSkip());

  return false;
}

/// Returns a full representation string for a [directive]
String _dumpDirective(Directive directive) {
  final Directive(:name, :parameters) = directive;
  return '${_directiveIndicator.asString()}$name ${parameters.join(' ')}';
}

/// Validates a tag uri. Returns it if valid. Otherwise, an exception is thrown.
///
/// Internally calls [_parseTagUri].
String _ensureIsTagUri(String uri, {required bool allowRestrictedIndicators}) {
  return _parseTagUri(
    UnicodeIterator.ofString(uri),
    allowRestrictedIndicators: allowRestrictedIndicators,
  );
}

/// Parses a `YAML` tag uri.
///
/// [allowRestrictedIndicators] - ignores YAML guidelines to have
/// `!, [,  ], {, }` escaped in tag uri characters. This should only be set to
/// `true` when parsing a [GlobalTag] which is not allowed in a top
/// level/key/value scalar.
///
/// [isVerbatim] - indicates whether a tag uri for a [VerbatimTag] is being
/// parsed. When `true`, the closing `>` is allowed and parsing terminates
/// after it is encountered.
///
/// [isAnchorOrAlias] - treats the uri characters being parsed as characters
/// of an `alias` or `anchor` to/for a [Node] respectively. Defaults
/// [isVerbatim] and [allowRestrictedIndicators] to `false`.
String _parseTagUri(
  SourceIterator iterator, {
  required bool allowRestrictedIndicators,
  bool includeScheme = false,
  bool isVerbatim = false,
  StringBuffer? existingBuffer,
}) {
  final buffer = existingBuffer ?? StringBuffer();

  if (includeScheme) {
    _parseScheme(buffer, iterator);
  }

  tagParser:
  while (!iterator.isEOF) {
    final char = iterator.current;

    switch (char) {
      case lineFeed || carriageReturn || space || tab:
        break tagParser;

      // Parse as escaped hex %
      case _directiveIndicator:
        _parseHexInUri(iterator, buffer);

      // A verbatim tag ends immediately a ">" is seen
      case _verbatimEnd when isVerbatim:
        break tagParser;

      // Prefer exiting immediately a flow delimiter is encountered.
      case _ when !allowRestrictedIndicators && char.isFlowDelimiter():
        break tagParser;

      /// Tag indicators must be escaped when parsing tags
      case tag:
        throwWithSingleOffset(
          iterator,
          message: 'Tag indicator must escaped when used as a URI character',
          offset: iterator.currentLineInfo.current,
        );

      case _ when isUriChar(char):
        buffer.writeCharCode(char);

      default:
        throwWithSingleOffset(
          iterator,
          message: 'The current character is not a valid URI character',
          offset: iterator.currentLineInfo.current,
        );
    }

    iterator.nextChar();
  }

  return buffer.toString();
}

/// Parses a URI scheme
void _parseScheme(StringBuffer buffer, SourceIterator iterator) {
  int? lastChar;
  const schemeEnd = mappingValue; // ":" char

  takeFromIteratorUntil(
    iterator,
    includeCharAtCursor: true,
    mapper: (c) => c,
    onMapped: (s) {
      lastChar = s;
      buffer.writeCharCode(s);
    },
    stopIf: (_, c) {
      return iterator.current == schemeEnd || !isUriChar(c);
    },
  );

  // We must have a ":" as the last char
  if (lastChar != schemeEnd) {
    throwWithSingleOffset(
      iterator,
      message: 'Invalid URI scheme in tag uri',
      offset: iterator.currentLineInfo.current,
    );
  }

  /// Ensure we return in a state where a tag uri can be parsed further
  if (iterator.peekNextChar().isNullOr((c) => !isUriChar(c))) {
    throwForCurrentLine(
      iterator,
      message: 'Expected at least a uri character after the scheme',
    );
  }

  iterator.nextChar(); // Parsing can continue
}

/// Parses a URI character escaped with `%`
void _parseHexInUri(SourceIterator iterator, StringBuffer uriBuffer) {
  const hexCount = 2;

  final hexBuff = StringBuffer('0x');

  if (takeFromIteratorUntil(
        iterator,
        includeCharAtCursor: false,
        mapper: (char) => char,
        onMapped: hexBuff.writeCharCode,
        stopIf: (count, next) => !next.isHexDigit() || count == hexCount,
      ) !=
      hexCount) {
    throwWithApproximateRange(
      iterator,
      message: 'Expected at least 2 hex digits',
      current: iterator.currentLineInfo.current,

      /// We have highlight the "%" that indicated this is an hex. This will
      /// help provide accurate and contextual information. The buffer
      /// indicates how many characters we have read so far. Its baseline is 2,
      /// such that:
      ///   - If we read 1 char, (3 - 2) = 1. So we have to highlight 1 char
      ///     behind.
      ///   - If we read 0 chars, (2 - 2) = 0. So have to highlight 0 chars
      ///     behind.
      charCountBefore: hexBuff.length - hexCount,
    );
  }

  uriBuffer.write(String.fromCharCode(int.parse(hexBuff.toString())));
}

/// Parses an alias or anchor suffix.
String parseAnchorOrAliasTrailer(SourceIterator iterator) {
  final buffer = StringBuffer();

  // [parseNodeProperties] always skips leading "&" and "*"
  do {
    /// Allows only non-space characters. Prefer quick exit once a flow
    /// delimiter is encountered.
    if (!iterator.isEOF &&
        !iterator.current.isFlowDelimiter() &&
        iterator.current.isNonSpaceChar()) {
      buffer.writeCharCode(iterator.current);
      iterator.nextChar();
      continue;
    }

    break;
  } while (true);

  // Anchor/alias must have at least 1 char after "&"/"*" respectively.
  if (buffer.isEmpty) {
    const message = 'Expected at 1 non-whitespace character';
    final offset = iterator.currentLineInfo.current;

    iterator.hasNext
        ? throwWithSingleOffset(iterator, message: message, offset: offset)
        : throwWithApproximateRange(
            iterator,
            message: message,
            current: offset,
            charCountBefore: 1,
          );
  }

  return buffer.toString();
}
