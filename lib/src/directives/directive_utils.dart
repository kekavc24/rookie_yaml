part of 'directives.dart';

/// Returns a full `YAML` string representation of [YamlDirective]
String _dumpDirective(Directive directive) {
  final space = WhiteSpace.space.string;

  final Directive(:name, :parameters) = directive;

  final buffer =
      StringBuffer(_directiveIndicator.string)
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
String _parseTagUri(
  ChunkScanner scanner, {
  required bool allowRestrictedIndicators,
  bool isVerbatim = false,
}) {
  final buffer = StringBuffer();

  const hexCount = 2;

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
      case _directiveIndicator:
        parseHex();

      // A verbatim tag ends immediately a ">" is seen
      case _ when string == _verbatimEnd.string && isVerbatim:
        break tagParser;

      /// YAML insists that these characters must be escaped.
      ///
      /// However, a global tag uri can have them unescaped as long as it
      /// doesn't begin with `!`. This degenerates it to a local tag prefix
      /// that may treat the uri as a named tag handle prefix.
      ///
      /// While our parsing strategy may prevent this, it is imperative to
      /// have predictable behaviour that matches the schema!
      ///
      /// TODO: Move to isUriChar case?
      case _
          when !allowRestrictedIndicators &&
              (flowDelimiters.contains(char) || char == _tagIndicator):
        throw FormatException(
          'Expected "${char.string}" to be escaped. '
          'Flow collection characters and the "${_tagIndicator.string}" '
          'character must be escaped.',
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
