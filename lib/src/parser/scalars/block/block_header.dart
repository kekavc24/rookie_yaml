part of 'block_scalar.dart';

/// Parses a block scalar's header info. `YAML` recommends that the first
/// should only include the block and chomping indicators or a comment
/// restricted to a single line.
_BlockHeaderInfo _parseBlockHeader(
  ChunkScanner scanner, {
  required void Function(YamlComment comment) onParseComment,
}) {
  var current = scanner.charAtCursor;
  final isLiteral = _isLiteralIndicator(current);

  if (isLiteral == null) {
    throw FormatException(
      '${current?.string ?? ''} is not a valid block style indicator',
    );
  }

  /// Runs and updates the value at the cursor for evaluation
  T functionDelegate<T>(T Function() runnable) {
    final val = runnable();
    current = scanner.charAtCursor;
    return val;
  }

  void skipChar() => functionDelegate(scanner.skipCharAtCursor);

  // Skip literal indicator
  skipChar();

  // TODO: Should block headers terminate with line break at all times?
  if (current == null) {
    return (
      isLiteral: isLiteral,
      chomping: ChompingIndicator.clip, // Default chomping indicator
      indentIndicator: null,
    );
  }

  final (chomping, indentIndicator) = functionDelegate(
    () => _extractIndicators(scanner),
  );

  // Skip whitespace
  if (current is WhiteSpace) {
    functionDelegate(() => scanner.skipWhitespace(skipTabs: true));
    skipChar(); // Must always skip char at cursor. We peek ahead.
  }

  // Extract any comments
  if (current == Indicator.comment) {
    if (scanner.charBeforeCursor is! WhiteSpace) {
      throw FormatException(
        'Expected a whitespace character before the start of the comment',
      );
    }

    functionDelegate(() => onParseComment(parseComment(scanner).comment));
  } else if (current == LineBreak.carriageReturn &&
      scanner.peekCharAfterCursor() == LineBreak.lineFeed) {
    skipChar();
  }

  // TODO: Should block headers terminate with line break at all times?
  if (current != null && current != LineBreak.lineFeed) {
    throw _charNotAllowedException(current!.string);
  }

  return (
    isLiteral: isLiteral,
    chomping: chomping,
    indentIndicator: indentIndicator,
  );
}

const _indentationException = FormatException(
  'Invalid block indentation indicator. Value must be between 1 - 9',
);

/// Parses block indentation and chomping indicators
_IndicatorInfo _extractIndicators(ChunkScanner scanner) {
  ChompingIndicator? chomping;
  int? indentIndicator;

  // We only read 2 characters
  for (var count = 0; count < 2; count++) {
    final char = scanner.charAtCursor;

    if (char case null || LineBreak _ || WhiteSpace _) break;

    final ReadableChar(string: charAsStr) = char;

    if (isDigit(char)) {
      // Allows only a single digit between 1 - 9
      if (indentIndicator != null) {
        throw _indentationException;
      }

      indentIndicator = int.parse(charAsStr);

      RangeError.checkValueInInterval(
        indentIndicator,
        1,
        9,
        null,
        _indentationException.message,
      );
    } else {
      // We must not see duplicate chomping indicators or any other char
      if (chomping != null) {
        throw FormatException(
          'Duplicate chomping indicators not allowed! Already declared'
          ' "$chomping" but found "$charAsStr"',
        );
      }

      chomping = _resolveChompingIndicator(char);

      if (chomping == null) {
        /// Break once we see comment. Let it bubble up and be handled by the
        /// function parsing the block header
        if (charAsStr == '#') break;

        throw _charNotAllowedException(charAsStr);
      }
    }

    scanner.skipCharAtCursor();
  }

  return (chomping ?? ChompingIndicator.clip, indentIndicator);
}
