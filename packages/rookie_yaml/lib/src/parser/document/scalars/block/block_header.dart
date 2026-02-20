part of 'block_scalar.dart';

/// Parses a block scalar's header info. `YAML` recommends that the first
/// should only include the block and chomping indicators or a comment
/// restricted to a single line.
_BlockHeaderInfo _parseBlockHeader(
  SourceIterator iterator, {
  required void Function(YamlComment comment) onParseComment,
}) {
  final isLiteral = _isLiteralIndicator(iterator.current);

  if (isLiteral == null) {
    throwWithSingleOffset(
      iterator,
      message: 'The current char is not a valid block style indicator',
      offset: iterator.currentLineInfo.current,
    );
  }

  // Skip literal indicator
  iterator.nextChar();

  // TODO: Should block headers terminate with line break at all times?
  if (iterator.isEOF) {
    return (
      isLiteral: isLiteral,
      chomping: ChompingIndicator.clip, // Default chomping indicator
      indentIndicator: null,
    );
  }

  final (chomping, indentIndicator) = _extractIndicators(iterator);

  // Skip whitespace
  if (iterator.current case space || tab) {
    skipWhitespace(iterator, skipTabs: true);
    iterator.nextChar();
  }

  // Extract any comments
  if (iterator.current == comment) {
    if (iterator.before case space || tab) {
      onParseComment(parseComment(iterator).comment);
    } else {
      throwWithSingleOffset(
        iterator,
        message:
            'Expected a whitespace character before the start of the comment',
        offset: iterator.currentLineInfo.current,
      );
    }
  }

  // TODO: Should block headers terminate with line break at all times?
  if (iterator.isEOF || iterator.current.isLineBreak()) {
    return (
      isLiteral: isLiteral,
      chomping: chomping,
      indentIndicator: indentIndicator,
    );
  }

  _charNotAllowedException(iterator);
}

const _indentationErr =
    'Invalid block indentation indicator. Value must be between 1 - 9';

/// Parses block indentation and chomping indicators
_IndicatorInfo _extractIndicators(SourceIterator iterator) {
  ChompingIndicator? chomping;
  int? indentIndicator;

  // We only read 2 characters
  for (var count = 0; count < 2; count++) {
    final char = iterator.current;

    if (iteratedIsEOF(char) || char.isLineBreak() || char.isWhiteSpace()) break;

    if (char.isDigit()) {
      // Allows only a single digit between 1 - 9
      if (indentIndicator != null) {
        throwWithApproximateRange(
          iterator,
          message: _indentationErr,
          current: iterator.currentLineInfo.current,
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
          iterator,
          message: 'Duplicate chomping indicators not allowed!',
          current: iterator.currentLineInfo.current,
          charCountBefore: 1, // Include chomping indicator before
        );
      }

      chomping = _resolveChompingIndicator(char);

      if (chomping == null) {
        // Break once we see comment. Let it bubble up and be handled by the
        // function parsing the block header
        if (char == comment) break;

        _charNotAllowedException(iterator);
      }
    }

    iterator.nextChar();
  }

  return (chomping ?? ChompingIndicator.clip, indentIndicator);
}
