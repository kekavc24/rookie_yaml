part of 'chunk_scanner.dart';

typedef GraphemeSourceSpan = Offset;
const _emptyIterable = Iterable<LineSpanChar>.empty();

/// A span representing a collection of grapheme clusters/utf8 characters.
/// Simply, a collection of human readable characters in a line.
///
/// This implementation assumes a new line starts after a `\n` character
final class LineSpan {
  LineSpan({
    required this.lineIndex,
    required bool hasLineBreak,
    required int startOffset,
    required Characters characters,
  }) : _shouldEmitEndToken = hasLineBreak,
       _startOffset = startOffset,
       _endOffset = startOffset,
       source = characters.string {
    if (source.isEmpty) {
      _hasNextChar = false;
      _charQueue = _emptyIterable.iterator;
      return;
    }

    _charQueue =
        characters
            .mapIndexed((index, char) => LineSpanChar.wrap(char, index))
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

  /// Start offset in the entire string to which [source] represents a portion
  /// of it or its entirety.
  final int _startOffset;

  int _endOffset;

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
  LineSpanChar? get peekNextChar =>
      _hasNextChar
          ? _charQueue.current
          : _canEmitEOL
          ? LineSpanChar.terminal(_currentIndex + 1)
          : null;

  /// Number of characters iterated in this line span
  int get charsIterated => _currentIndex + 1;

  /// Returns the offset of this line that has been iterated.
  ///
  /// By default, if the iteration has not started, the `start` and `end`
  /// offset will both be `-1`.
  ///
  /// Otherwise, the `end` offset will be equal to the offset of the last
  /// character iterated.
  GraphemeSourceSpan get offset {
    if (charsIterated == 0) return (start: _currentIndex, end: _currentIndex);

    // Add 1 to exclude the last character
    return (start: _startOffset, end: _endOffset + 1);
  }

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
        char = LineSpanChar.terminal(++_currentIndex);
        _emittedEndToken = true;

      default:
        throw StateError(
          'Line $lineIndex: No more characters present in this line',
        );
    }

    ++_endOffset;
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
  LineSpanChar._(this.character, this.columnIndex);

  /// Wraps a single character within a string/line.
  factory LineSpanChar.wrap(String char, int index) {
    final wrapped = char.isEmpty ? LineBreak.lineFeed : GraphemeChar.wrap(char);
    return LineSpanChar._(delimiterMap[wrapped.unicode] ?? wrapped, index);
  }

  LineSpanChar.terminal(int index) : this._(LineBreak.lineFeed, index);

  /// A single character within a line.
  final ReadableChar character;

  @override
  final int columnIndex;

  @override
  bool get isLastChar =>
      character is LineBreak && character == LineBreak.lineFeed;

  @override
  String toString() => character.string;
}
