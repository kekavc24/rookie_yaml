part of 'grapheme_scanner.dart';

/// Represents an exception throw when parsing of a YAML source string fails.
final class YamlParseException implements Exception {
  YamlParseException(
    this.message, {
    required this.lineInfo,
    required this.highlight,
  });

  /// Last offset before this error was thrown. Typically the offset closely
  /// associated with the error.
  final RuneOffset lineInfo;

  /// Error message.
  final String message;

  /// Highlighted line(s) associated with the error.
  final String highlight;

  @override
  String toString() {
    final (:lineIndex, :columnIndex, :utfOffset) = lineInfo;
    return 'ParserException'
        '[Line $lineIndex, Column $columnIndex, Offset $utfOffset]: '
        '$message\n\n'
        '$highlight';
  }
}

/// Ensures the current line at the provided [index] is read until a line
/// terminator is found or no more characters are present (whichever comes
/// first) and returns the underlying iterator used by the [scanner].
///
/// If [index] is `null`, then the most recent line is buffered until a line
/// terminator is found.
SourceIterator _makeLineAvailable(GraphemeScanner scanner, [int? index]) {
  final iterator = scanner._iterator;
  final lineIndex = index ?? iterator.currentLine;

  while (iterator.hasNext && lineIndex >= iterator.currentLine) {
    iterator.nextChar();
  }

  return iterator;
}

const _caret = '^';
const _space = ' ';

/// Normalizes all escapes characters and applies [_caret]s to all [indices]
/// speified.
String _applyCarets(Iterable<int> chars, {required Set<int> indices}) {
  // We never throw when we plan to throw!
  if (indices.isEmpty) {
    return String.fromCharCodes(chars);
  }

  final content = <String>[];
  final highlight = <String>[];

  void maybePushHighlight(int index, int count) {
    final str = indices.remove(index) ? _caret : _space;

    // Keep it simple :)
    for (var i = 0; i < count; i++) {
      highlight.add(str);
    }
  }

  for (final (index, char) in chars.indexed) {
    final normalized = char
        .normalizeEscapedChars(
          includeTab: true,
          includeLineBreaks: true,
          includeDoubleQuote: false,
          includeSlashes: false,
        )
        .map((i) => i.asString())
        .toList();

    content.addAll(normalized);

    /// Icky (spacially inefficient) implementation. Will circle back.
    ///
    /// Some lines with errors may have an end offset nearer to the start
    /// which clears any offsets that need to be highlighted quite early.
    /// At that point, we are just trying to provide the current line's
    /// state as if the parser has read it but was never parsed.
    ///
    ///   "Oh lexer, my lexer,
    ///    Where art thou?"
    if (indices.isEmpty) continue;
    maybePushHighlight(index, normalized.length);
  }

  return '${content.join()}\n${highlight.join()}';
}

/// Returns an iterable that is not empty and can be highlighted.
///
/// This is important for empty lines. The iterable, if empty, is replaced with
/// a list which has a single space.
Iterable<int> _nonEmpty(Iterable<int> chars) => chars.isEmpty ? [space] : chars;

/// Highlights all [chars] from the [startIndex].
String _spannedHighlight(Iterable<int> chars, int startIndex) {
  final target = _nonEmpty(chars);
  return _applyCarets(
    target,
    indices: Iterable<int>.generate(
      target.length - startIndex,
      (index) => startIndex + index,
    ).toSet(),
  );
}

/// Throws a [YamlParseException] pointing to a single char at the specified
/// [offset].
Never throwWithSingleOffset(
  GraphemeScanner scanner, {
  required String message,
  required RuneOffset offset,
}) {
  final RuneOffset(:lineIndex, :columnIndex) = offset;
  final iterator = _makeLineAvailable(scanner, lineIndex);

  // Include previous line if present
  final lines = iterator.lines(startIndex: max(0, lineIndex - 1));

  var highlighted = lines.length > 1
      ? '${String.fromCharCodes(_nonEmpty(lines.first.chars))}\n'
      : '';

  highlighted += _applyCarets(
    _nonEmpty((lines.lastOrNull ?? SourceLine(0, 0, chars: [space])).chars),
    indices: {columnIndex},
  );

  throw YamlParseException(message, lineInfo: offset, highlight: highlighted);
}

/// Throws a [YamlParseException] for range of [lines] where the last line has
/// the specified [end] offset. The [startIndex] acts as the column index for
/// the first line if [lines] has more than 1 line. Otherwise, the column index
/// is treated as an column index to the last line.
Never _rangedThrow(
  String message,
  int startIndex,
  RuneOffset end,
  List<SourceLine> lines,
) {
  var columnIndex = startIndex;
  var length = lines.length - 1;
  final buffer = StringBuffer();

  if (length >= 1) {
    --length;
    buffer.writeln(
      /// Basic maths for any array dictates that the starting index indicates
      /// the number of elements we have to skip. The first line may have an
      /// offset that is ahead
      _spannedHighlight(lines.first.chars.skip(columnIndex), 0),
    );

    columnIndex = 0; // Reset. First line captured this index.

    // Non-terminating lines are highlighted from start to the end
    for (final line in lines.skip(1).take(length)) {
      buffer.writeln(_spannedHighlight(line.chars, 0));
    }
  }

  /// Avoid using [spannedHighlight]. We have the end index and we also want to
  /// show the line to the end but with a ranged highlight
  buffer.write(
    _applyCarets(
      _nonEmpty(lines.last.chars),
      indices: Iterable<int>.generate(
        (end.columnIndex + 1) - columnIndex,
        (i) => columnIndex + i,
      ).toSet(),
    ),
  );

  throw YamlParseException(
    message,
    lineInfo: end,
    highlight: buffer.toString(),
  );
}

/// Throw a [YamlParseException] with the current active line whose characters
/// are being iterated. The line is highlighted from the start to the end.
Never throwForCurrentLine(
  GraphemeScanner scanner, {
  required String message,
  RuneOffset? end,
}) {
  final (:start, :current) = scanner.lineInfo();
  return throwWithRangedOffset(
    scanner,
    message: message,
    start: start,
    end: end ?? current,
  );
}

/// Throws a [YamlParseException] for a source string with the [start] and [end]
/// offset specified.
Never throwWithRangedOffset(
  GraphemeScanner scanner, {
  required String message,
  required RuneOffset start,
  required RuneOffset end,
}) {
  final (:lineIndex, :columnIndex, :utfOffset) = start;

  if (utfOffset > end.utfOffset) {
    return throwWithSingleOffset(
      scanner,
      message: message,
      offset: start,
    );
  }

  return _rangedThrow(
    message,
    columnIndex,
    end,
    _makeLineAvailable(
      scanner,
      end.lineIndex,
    ).lines(startIndex: lineIndex),
  );
}

/// Throws a [YamlParseException] for a source string with an end offset at the
/// [current] offset and a start offset approximately at least [charCountBefore]
/// behind.
///
/// [charCountBefore] doesn't include the character at the [current] offset.
Never throwWithApproximateRange(
  GraphemeScanner scanner, {
  required String message,
  required RuneOffset current,
  required int charCountBefore,
}) {
  final RuneOffset(:columnIndex, :lineIndex) = current;
  final linesAvailable = _makeLineAvailable(scanner, lineIndex).lines();

  final lines = <SourceLine>[linesAvailable.last];
  var offsetDiff = columnIndex - charCountBefore;

  var iterIndex = lineIndex - 1;

  // Iterate in reverse as look for the starting point
  while (iterIndex >= 0 && offsetDiff < 0) {
    final line = linesAvailable[iterIndex];
    lines.add(line);

    /// Unlike the last line which uses column index, just use the total number
    /// of characters in the current line. We just need to compensate for the
    /// transition of the line break from one line to the next
    offsetDiff = offsetDiff + line.chars.length + 1;
    --iterIndex;
  }

  return _rangedThrow(message, max(0, offsetDiff), current, lines);
}
