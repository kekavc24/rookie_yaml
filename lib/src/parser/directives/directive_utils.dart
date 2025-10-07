part of 'directives.dart';

/// Returns a full `YAML` string representation of [YamlDirective]
String _dumpDirective(Directive directive) {
  final separation = String.fromCharCode(space);

  final Directive(:name, :parameters) = directive;

  final buffer = StringBuffer()
    ..writeCharCode(_directiveIndicator)
    ..write(name)
    ..write(separation)
    ..write(parameters.join(separation));
  return buffer.toString();
}

/// Validates a tag uri. Returns it if valid. Otherwise, an exception is thrown.
///
/// Internally calls [_parseTagUri].
String _ensureIsTagUri(String uri, {required bool allowRestrictedIndicators}) {
  return _parseTagUri(
    GraphemeScanner(UnicodeIterator.ofString(uri)),
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
  GraphemeScanner scanner, {
  required bool allowRestrictedIndicators,
  bool includeScheme = false,
  bool isVerbatim = false,
  bool isAnchorOrAlias = false,
  StringBuffer? existingBuffer,
}) {
  final allowFlowIndicators = !isAnchorOrAlias && allowRestrictedIndicators;
  final isVerbatimUri = !isAnchorOrAlias && isVerbatim;

  final buffer = existingBuffer ?? StringBuffer();

  if (includeScheme) {
    _parseScheme(buffer, scanner);
  }

  tagParser:
  while (scanner.canChunkMore) {
    final char = scanner.charAtCursor!;

    switch (char) {
      case lineFeed || carriageReturn || space || tab:
        break tagParser;

      // Parse as escaped hex %
      case _directiveIndicator when !isAnchorOrAlias:
        _parseHexInUri(scanner, buffer);

      // A verbatim tag ends immediately a ">" is seen
      case _verbatimEnd when isVerbatimUri:
        break tagParser;

      /// Flow indicators must be escaped with `%` if parsing a tag uri.
      ///
      /// Alias/anchor names does not allow them.
      case _ when !allowFlowIndicators && char.isFlowDelimiter():
        {
          if (isAnchorOrAlias) break tagParser;

          throw FormatException(
            'Expected "${char.asString()}" to be escaped. '
            'Flow collection characters must be escaped.',
          );
        }

      /// Tag indicators must be escaped when parsing tags
      case tag when !isAnchorOrAlias:
        throw FormatException(
          'Expected "!" to be escaped. The "!" character must be escaped.',
        );

      case _ when isUriChar(char):
        buffer.writeCharCode(char);

      default:
        throw FormatException('"${char.asString()}" is not a valid URI char');
    }

    scanner.skipCharAtCursor();
  }

  return buffer.toString();
}

void _parseScheme(StringBuffer buffer, GraphemeScanner scanner) {
  int? lastChar;
  const schemeEnd = mappingValue; // ":" char

  scanner.takeUntil(
    includeCharAtCursor: true,
    mapper: (c) => c,
    onMapped: (s) {
      lastChar = s;
      buffer.writeCharCode(s);
    },
    stopIf: (_, c) {
      return scanner.charAtCursor == schemeEnd || !isUriChar(c);
    },
  );

  // We must have a ":" as the last char
  if (lastChar != schemeEnd) {
    throw FormatException('Invalid URI scheme in tag uri');
  }

  /// Ensure we return in a state where a tag uri can be parsed further
  if (scanner.charAfter.isNullOr((c) => !isUriChar(c))) {
    throw FormatException('Expected at least a uri character after the scheme');
  }

  scanner.skipCharAtCursor(); // Parsing can continue
}

void _parseHexInUri(GraphemeScanner scanner, StringBuffer uriBuffer) {
  const hexCount = 2;

  final hexBuff = StringBuffer('0x');

  if (scanner.takeUntil(
        includeCharAtCursor: false,
        mapper: (char) => char.asString(),
        onMapped: (mapped) => hexBuff.write(mapped),
        stopIf: (count, next) => !next.isHexDigit() || count == hexCount,
      ) !=
      hexCount) {
    throw FormatException('Invalid escaped hex found in tag URI => "$hexBuff"');
  }

  uriBuffer.write(String.fromCharCode(int.parse(hexBuff.toString())));
}

/// Parses an alias or anchor name.
String parseAnchorOrAlias(GraphemeScanner scanner) => _parseTagUri(
  scanner,
  allowRestrictedIndicators: false,
  isVerbatim: false,
  isAnchorOrAlias: true,
);
