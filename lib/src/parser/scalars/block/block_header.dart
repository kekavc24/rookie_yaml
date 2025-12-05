part of 'block_scalar.dart';

/// Parses a block scalar's header info. `YAML` recommends that the first
/// should only include the block and chomping indicators or a comment
/// restricted to a single line.
_BlockHeaderInfo _parseBlockHeader(
  GraphemeScanner scanner, {
  required void Function(YamlComment comment) onParseComment,
}) {
  final isLiteral = _isLiteralIndicator(scanner.charAtCursor);

  if (isLiteral == null) {
    throwWithSingleOffset(
      scanner,
      message: 'The current char is not a valid block style indicator',
      offset: scanner.lineInfo().current,
    );
  }

  // Skip literal indicator
  scanner.skipCharAtCursor();

  // TODO: Should block headers terminate with line break at all times?
  if (scanner.charAtCursor == null) {
    return (
      isLiteral: isLiteral,
      chomping: ChompingIndicator.clip, // Default chomping indicator
      indentIndicator: null,
    );
  }

  final (chomping, indentIndicator) = _extractIndicators(scanner);

  // Skip whitespace
  if (scanner.charAtCursor case space || tab) {
    scanner
      ..skipWhitespace(skipTabs: true)
      ..skipCharAtCursor();
  }

  // Extract any comments
  if (scanner.charAtCursor.isNotNullAnd((c) => c == comment)) {
    if (scanner.charBeforeCursor case space || tab) {
      onParseComment(parseComment(scanner).comment);
    } else {
      throwWithSingleOffset(
        scanner,
        message:
            'Expected a whitespace character before the start of the comment',
        offset: scanner.lineInfo().current,
      );
    }
  }

  // TODO: Should block headers terminate with line break at all times?
  if (!scanner.charAtCursor.isNullOr((c) => c.isLineBreak())) {
    _charNotAllowedException(scanner);
  }

  return (
    isLiteral: isLiteral,
    chomping: chomping,
    indentIndicator: indentIndicator,
  );
}

const _indentationErr =
    'Invalid block indentation indicator. Value must be between 1 - 9';

/// Parses block indentation and chomping indicators
_IndicatorInfo _extractIndicators(GraphemeScanner scanner) {
  ChompingIndicator? chomping;
  int? indentIndicator;

  // We only read 2 characters
  for (var count = 0; count < 2; count++) {
    final char = scanner.charAtCursor;

    if (char.isNullOr((c) => c.isLineBreak() || c.isWhiteSpace())) break;

    if (char!.isDigit()) {
      // Allows only a single digit between 1 - 9
      if (indentIndicator != null) {
        throwWithApproximateRange(
          scanner,
          message: _indentationErr,
          current: scanner.lineInfo().current,
          charCountBefore: 1, // Include the previous digit we read
        );
      }

      indentIndicator = char - asciiZero;

      RangeError.checkValueInInterval(
        indentIndicator,
        1,
        9,
        null,
        _indentationErr,
      );
    } else {
      // We must not see duplicate chomping indicators or any other char
      if (chomping != null) {
        throwWithApproximateRange(
          scanner,
          message: 'Duplicate chomping indicators not allowed!',
          current: scanner.lineInfo().current,
          charCountBefore: 1, // Include chomping indicator before
        );
      }

      chomping = _resolveChompingIndicator(char);

      if (chomping == null) {
        /// Break once we see comment. Let it bubble up and be handled by the
        /// function parsing the block header
        if (char == comment) break;

        _charNotAllowedException(scanner);
      }
    }

    scanner.skipCharAtCursor();
  }

  return (chomping ?? ChompingIndicator.clip, indentIndicator);
}
