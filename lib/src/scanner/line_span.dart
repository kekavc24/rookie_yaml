part of 'chunk_scanner.dart';

typedef LineRangeInfo = ({SourceLocation start, SourceLocation current});

const _emptyIterable = Iterable<LineSpanChar>.empty();

/// A span representing a collection of grapheme clusters/utf8 characters.
/// Simply, a collection of human readable characters in a line.
///
/// This implementation assumes a new line starts after a `\n` character
final class LineSpan {
  /// Initializes a [LineSpan].
  ///
  /// [lineIndex] represent current index of the line.
  ///
  /// [hasLineBreak] indicates if a `linefeed` should be emitted after all
  /// characters of the line have been read. TYpically `true` for any line that
  /// is not the last.
  ///
  /// [startOffset] index of the first character in the lin in the string
  /// source.
  ///
  /// [characters] an iterable of `Grapheme` clusters in the string, that is,
  /// a human readable UTF character.
  LineSpan({
    required this.lineIndex,
    required bool hasLineBreak,
    required int startOffset,
    required Characters characters,
  }) : _shouldEmitEndToken = hasLineBreak,
       _start = SourceLocation(startOffset, line: lineIndex, column: 0),
       source = characters.string {
    _current = _start;

    if (source.isEmpty) {
      _hasNextChar = false;
      _charQueue = _emptyIterable.iterator;
      return;
    }

    _charQueue = characters
        .mapIndexed((index, char) => LineSpanChar._(char.runes.first, index))
        .iterator;
    _hasNextChar = _charQueue.moveNext();
  }

  /// Index of this line
  final int lineIndex;

  /// Indicates if this span should emit an end of line token once no more
  /// tokens are available.
  ///
  /// Typically a [LineBreak.lineFeed] character. This is important if there
  /// more lines or the current line ended with a [LineBreak.lineFeed]
  /// character.
  final bool _shouldEmitEndToken;

  final SourceLocation _start;

  late SourceLocation _current;

  /// Collection of characters in line
  late final Iterator<LineSpanChar> _charQueue;

  /// Tracks the index of the current character. Basically, its column index.
  int _currentIndex = -1;

  /// Tracks whether there are more characters in this line
  bool _hasNextChar = false;

  /// Tracks whether we emmitted an end of line token. This is just
  /// [LineSpanChar] with a [LineBreak.lineFeed] character.
  bool _emittedEndToken = false;

  bool get _canEmitEOL => _shouldEmitEndToken && !_emittedEndToken;

  /// Peeks next char without moving the iterator forward.
  LineSpanChar? get peekNextChar => _hasNextChar
      ? _charQueue.current
      : _canEmitEOL
      ? LineSpanChar._terminal(_currentIndex + 1)
      : null;

  /// Number of characters iterated in this line span
  int get charsIterated => _currentIndex + 1;

  LineRangeInfo get lineRangeInfo => (start: _start, current: _current);

  /// Obtains the current character in the line under the cursor and moves the
  /// cursor forward.
  LineSpanChar nextChar() {
    LineSpanChar char;

    // Intentional, can be `if` statements ¯\_(ツ)_/¯
    switch (_hasNextChar) {
      case true:
        char = _charQueue.current;
        _currentIndex = char.columnIndex;
        _hasNextChar = _charQueue.moveNext();

      case _ when _canEmitEOL:
        // Update current index, base on last character emitted
        char = LineSpanChar._terminal(++_currentIndex);
        _emittedEndToken = true;

      default:
        throw StateError(
          'Line $lineIndex: No more characters present in this line',
        );
    }

    if (charsIterated > 1) {
      _current = SourceLocation(
        _start.offset + _currentIndex,
        line: lineIndex,
        column: char.columnIndex,
      );
    }

    return char;
  }

  /// Returns if this span has any more characters
  bool get hasMoreChars => _hasNextChar || _canEmitEOL;

  /// Source string of this line span.
  final String source;

  @override
  String toString() => source;
}

/// Utility mixin providing column information
abstract mixin class _LineColumnIntrinsics {
  /// Zero based column index for a character within a line
  int get columnIndex;

  /// Checks if this is the first character in the line.
  bool get isFirstChar => columnIndex == 0;

  /// Checks if this is the last character in the line.
  bool get isLastChar;
}

/// A wrapper class representing a single human readable character within
/// a [LineSpan].
final class LineSpanChar with _LineColumnIntrinsics {
  const LineSpanChar._(this.character, this.columnIndex);

  /// Last character of the line.
  const LineSpanChar._terminal(int index) : this._(lineFeed, index);

  /// A single character within a line.
  final int character;

  @override
  final int columnIndex;

  @override
  bool get isLastChar => character == lineFeed;

  @override
  String toString() => String.fromCharCode(character);
}
