part of 'directives.dart';

/// Returns a full `YAML` string representation of [YamlDirective]
String _dumpDirective(Directive directive) {
  final space = WhiteSpace.space.string;

  final Directive(:name, :parameters) = directive;

  final buffer = StringBuffer(_directiveIndicator.string)
    ..write(name)
    ..write(space)
    ..write(parameters.join(space));
  return buffer.toString();
}

/// Validates a tag uri. Returns it if valid. Otherwise, an exception is thrown.
///
/// Internally calls [_parseTagUri].
String _ensureIsTagUri(String uri, {required bool allowRestrictedIndicators}) {
  return _parseTagUri(
    ChunkScanner.of(uri),
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
  ChunkScanner scanner, {
  required bool allowRestrictedIndicators,
  bool includeScheme = false,
  bool isVerbatim = false,
  bool isAnchorOrAlias = false,
}) {
  final allowFlowIndicators = !isAnchorOrAlias && allowRestrictedIndicators;
  final isVerbatimUri = !isAnchorOrAlias && isVerbatim;

  final buffer = StringBuffer();

  const hexCount = 2;

  if (includeScheme) {
    _parseScheme(buffer, scanner);
  }

  void parseHex() {
    final hexBuff = StringBuffer('0x');

    final numHex = scanner.takeUntil(
      includeCharAtCursor: false,
      mapper: (char) => char.string,
      onMapped: (mapped) => hexBuff.write(mapped),
      stopIf: (count, next) {
        return !isHexDigit(next) || count == hexCount;
      },
    );

    final hex = hexBuff.toString();

    if (numHex != hexCount) {
      throw FormatException('Invalid escaped hex found in tag URI => "$hex"');
    }

    buffer.write(String.fromCharCode(int.parse(hex)));
  }

  tagParser:
  while (scanner.canChunkMore) {
    final char = scanner.charAtCursor!;
    final ReadableChar(:string) = char;

    switch (char) {
      case LineBreak _ || WhiteSpace _:
        break tagParser;

      // Parse as escaped hex %
      case _directiveIndicator when !isAnchorOrAlias:
        parseHex();

      // A verbatim tag ends immediately a ">" is seen
      case _ when string == _verbatimEnd.string && isVerbatimUri:
        break tagParser;

      /// Flow indicators must be escaped with `%` if parsing a tag uri.
      ///
      /// Alias/anchor names does not allow them.
      case _ when !allowFlowIndicators && flowDelimiters.contains(char):
        {
          if (isAnchorOrAlias) {
            throw FormatException(
              'Anchor/alias names must not contain flow indicators',
            );
          }

          throw FormatException(
            'Expected "${char.string}" to be escaped. '
            'Flow collection characters must be escaped.',
          );
        }

      /// Tag indicators must be escaped when parsing tags
      case _ when !isAnchorOrAlias && char == _tagIndicator:
        throw FormatException(
          'Expected "${char.string}" to be escaped. '
          'The "${_tagIndicator.string}" character must be escaped.',
        );

      case _ when isUriChar(char):
        buffer.write(string);

      default:
        throw FormatException('"$string" is not a valid URI char');
    }

    scanner.skipCharAtCursor();
  }

  return buffer.toString();
}

void _parseScheme(StringBuffer buffer, ChunkScanner scanner) {
  var lastChar = '';
  const schemeEnd = Indicator.mappingValue; // ":" char

  scanner.takeUntil(
    includeCharAtCursor: true,
    mapper: (c) => c.string,
    onMapped: (s) {
      lastChar = s;
      buffer.write(s);
    },
    stopIf: (_, c) {
      return !isUriChar(c) || scanner.charAtCursor == schemeEnd;
    },
  );

  // We must have a ":" as the last char
  if (lastChar != schemeEnd.string) {
    throw FormatException('Invalid URI scheme in tag uri');
  }

  /// Ensure we return in a state where a tag uri can be parsed further
  if (scanner.peekCharAfterCursor() case ReadableChar? char
      when char == null || !isUriChar(char)) {
    throw FormatException('Expected at least a uri character after the scheme');
  }

  scanner.skipCharAtCursor(); // Parsing can continue
}

/// Parses an alias or anchor name.
String parseAnchorOrAlias(ChunkScanner scanner) => _parseTagUri(
  scanner,
  allowRestrictedIndicators: false,
  isVerbatim: false,
  isAnchorOrAlias: true,
);
