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

/// Normalizes a [tagSuffix] for a local tag uri. Any percent-encoded characters
/// are left untouched.
String _normalizeLocalTagUri(String tagSuffix) => _normalizeTagUri(
  UnicodeIterator.ofString(tagSuffix),
  includeRestricted: true,
);

/// Normalizes a tag uri present in the [iterator].
///
/// [bufferedUri] represents a buffer that was instantiated externally. Most
/// [GlobalTag] uri prefixes must be valid uri strings with a scheme and thus
/// require additional checks.
///
/// If [includeRestricted] is `true`, `!` and any flow collection delimiters
/// are percent-encoded.
///
/// See URI section: https://yaml.org/spec/1.2.2/#56-miscellaneous-characters
String _normalizeTagUri(
  UnicodeIterator iterator, {
  StringBuffer? bufferedUri,
  required bool includeRestricted,
}) {
  final buffer = bufferedUri ?? StringBuffer();

  /// Converts [char] as hex with '%' prefix.
  String asHex(int char) => '%${char.toRadixString(16)}';

  void addAsUriString(String string) =>
      buffer.write(Uri.encodeComponent(string));

  // Normalizes '%' or read the next two hext chars
  void normalized(int percent) {
    // Recover the '%'.
    if (iterator.peekNextChar().isNullOr((c) => !c.isHexDigit())) {
      buffer.write(asHex(percent));
      return;
    }

    // Fetch the next 2 hex characters
    final greedy = <int>[percent];

    while (greedy.length < 3) {
      iterator.nextChar();
      if (iterator.isEOF || !iterator.current.isHexDigit()) break;
      greedy.add(iterator.current);
    }

    final capture = String.fromCharCodes(greedy);
    greedy.length == 3 ? buffer.write(capture) : addAsUriString(capture);
  }

  while (!iterator.isEOF) {
    final char = iterator.current;

    switch (char) {
      case tag ||
              mappingStart ||
              mappingEnd ||
              flowSequenceStart ||
              flowEntryEnd ||
              flowSequenceEnd
          when includeRestricted:
        buffer.write(asHex(char));

      // %
      case directive:
        normalized(char);

      default:
        isUriChar(char)
            ? buffer.writeCharCode(char)
            : addAsUriString(char.asString());
    }

    if (iterator.peekNextChar() != null) {
      iterator.nextChar();
      continue;
    }

    break;
  }

  final buffered = buffer.toString();

  return buffered;
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
void _parseScheme(
  StringBuffer buffer,
  SourceIterator iterator, {
  bool isDecoding = true,
}) {
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
  if (isDecoding &&
      iterator.peekNextChar().isNullOr(
        (c) => !isUriChar(c) && c != directive, // %
      )) {
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

  var escaped = 0;
  final count = takeFromIteratorUntil(
    iterator,
    includeCharAtCursor: false,
    mapper: (char) => char,
    onMapped: (c) {
      escaped =
          (escaped << 4) |
          (c > asciiNine
              ? (10 + (c - (c > capF ? lowerA : capA)))
              : (c - asciiZero));
    },
    stopIf: (count, next) => !next.isHexDigit() || count == hexCount,
  );

  if (count != hexCount) {
    throwWithApproximateRange(
      iterator,
      message: 'Expected at least 2 hex digits',
      current: iterator.currentLineInfo.current,

      /// We have highlight the "%" that indicated this is an hex. This will
      /// help provide accurate and contextual information. The buffer
      /// indicates how many characters we have read so far.
      charCountBefore: (count + 2) - hexCount,
    );
  }

  uriBuffer.writeCharCode(escaped);
}

/// Parses an alias or anchor suffix.
String parseAnchorOrAliasTrailer(SourceIterator iterator) {
  final buffer = StringBuffer();

  /// Allows only non-space characters. Prefer quick exit once a flow
  /// delimiter is encountered.
  while (!iterator.isEOF &&
      !iterator.current.isFlowDelimiter() &&
      iterator.current.isNonSpaceChar()) {
    buffer.writeCharCode(iterator.current);
    iterator.nextChar();
    continue;
  }

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
