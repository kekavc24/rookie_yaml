part of 'directives.dart';

String _dumpDirective(_Directive directive) {
  final space = WhiteSpace.space.string;

  final _Directive(:name, :parameters) = directive;

  final buffer =
      StringBuffer(_directiveIndicator.string)
        ..write(name)
        ..write(space)
        ..write(parameters.join(space));
  return buffer.toString();
}

String _ensureIsTagUri(String uri, {required bool allowRestrictedIndicators}) {
  return _parseTagUri(
    ChunkScanner(source: uri)..skipCharAtCursor(),
    allowRestrictedIndicators: allowRestrictedIndicators,
  );
}

String _parseTagUri(
  ChunkScanner scanner, {
  required bool allowRestrictedIndicators,
}) {
  final buffer = StringBuffer();

  const hexCount = 2;

  void parseHex() {
    final hex =
        scanner
            .takeUntil(
              includeCharAtCursor: false,
              mapper: (char) => char.string,
              stopIf: (count, next) {
                return !isHexDigit(next) || count == hexCount;
              },
            )
            .join(); // Weird dart formatting

    if (hex.length != hexCount) {
      throw FormatException('Invalid escaped hex found in tag URI => "$hex"');
    }

    buffer.write(String.fromCharCode(int.parse('0x$hex')));
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
