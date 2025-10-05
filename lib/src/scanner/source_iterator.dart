import 'dart:io';

import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/scanner/chunk_scanner.dart';

/// Custom offset information.
///
/// `lineIndex` - represents the zero-based line index in the source string.<br>
/// `columnIndex` - represents the zero-based column index within a line.<br>
/// `utf16Index` - represents the zero-based index in the source string read as
/// a sequence of utf16 characters rather than utf8.
typedef RuneOffset = ({int lineIndex, int columnIndex, int utf16Index});

/// Returns start [RuneOffset] position of a line.
RuneOffset _getLineStart({int lineIndex = 0, int currentOffset = 0}) =>
    (lineIndex: lineIndex, columnIndex: 0, utf16Index: currentOffset);

/// Represents a span of chunk within a source string
typedef RuneSpan = ({RuneOffset start, RuneOffset end});

/// Represents the active line's span information. This is intentionally
/// different from [RuneSpan] because we prefer to iterate the source string
/// lazily and only split it when we encounter a `\n` terminator.
typedef LineInfo = ({RuneOffset start, RuneOffset current});

/// Represents a single line's source information with an inclusive start index
/// and end index. `chars` represents all characters that are not `\r` or `\n`
/// or `\r\n` within the line.
typedef Line = ({int startIndex, int inclusiveEndIndex, List<int> chars});

/// An iterator that iterates over any source parsable YAML source string
abstract interface class SourceIterator {
  /// Returns `true` if a char is present after the [current] char.
  bool get hasNext;

  /// Current character. Always points to the first character when this
  /// iterator is instantianted.
  ///
  /// Typically, this is the current character that the iterator **WAS**
  /// pointing to at [peekNextChar] before [nextChar] was called for any char
  /// other than the first char.
  int get current;

  /// Moves the iterator forward.
  ///
  /// Eagerly throws an [Error] rather than an [Exception] if called without
  /// checking [hasNext].
  void nextChar();

  /// Returns a non-null code point if the next character is present.
  int? peekNextChar();

  /// Returns the current line information which includes the start position
  /// of the current line and the current position of this iterator within
  /// the line.
  LineInfo get currentLineInfo;

  /// Returns the lines that have been iterated so far.
  List<Line> lines({int startIndex = 0});
}

/// A [SourceIterator] that iterates the utf16 unicode points of a source
/// string/file.
final class UnicodeIterator implements SourceIterator {
  UnicodeIterator._(this._iterator) {
    // Always point to the first character
    if (_iterator.moveNext()) {
      _currentChar = _iterator.current;

      if (!_iterator.moveNext()) {
        _bufferCurrent();
        _markLineAsComplete();
      } else {
        _hasNext = true;
        _nextChar = _iterator.current;

        _skipCarriageReturn();
      }

      return;
    }

    _lines.add(const (startIndex: 0, inclusiveEndIndex: 0, chars: []));
  }

  /// Creates a [UnicodeIterator] that uses the [RuneIterator] of the [source]
  /// string.
  UnicodeIterator.ofString(String source) : this._(source.runes.iterator);

  /// Creates a [UnicodeIterator] that synchronously reads the entire file from
  /// the [filePath] provided and uses the [Iterator] from its bytes.
  UnicodeIterator.ofFileSync(String filePath)
    : this._(File(filePath).readAsBytesSync().buffer.asUint16List().iterator);

  /// Actual iterator being read.
  final Iterator<int> _iterator;

  /// [Line]s lazily buffered while iterating.
  final _lines = <Line>[];

  /// UTF-16 unicode characters buffered for single [Line]. Always handed off
  /// without an additional copy operation.
  var _bufferedRunes = <int>[];

  /// Whether the [_iterator] has a character when `_iterator.current` is
  /// called.
  bool _hasNext = false;

  /// Start offset of the current [Line]
  RuneOffset _lineStartOffset = _getLineStart();

  /// Index of the UTF-8/UTF-16 unicode character in a string.
  int _graphemeIndex = 0;

  /// Index of the current line
  int _lineIndex = 0;

  /// Column index of the current character
  int _columnIndex = 0;

  /// Current character
  int _currentChar = -1;

  /// Next character
  int _nextChar = -1;

  @override
  bool get hasNext => _hasNext;

  @override
  int get current => _currentChar;

  @override
  void nextChar() {
    // Some defensive coding for the culture in case of refactors
    assert(
      _hasNext || _currentChar != -1,
      '[nextChar()] expects a non-empty char iterator',
    );

    var isNewLine = false;

    /// We always treat \r\n as a single character. Seeing a \r forces us to
    /// assume it is a line break. Keeping/tracking count serves no purpose
    /// since both are considered line breaks by YAML.
    if (_currentChar.isLineBreak()) {
      _markLineAsComplete();
      isNewLine = true;
    } else {
      _bufferedRunes.add(_currentChar);
    }

    _currentChar = _nextChar;
    _hasNext = _iterator.moveNext();
    _nextChar = _iterator.current;

    ++_graphemeIndex;

    //
    if (isNewLine) {
      ++_lineIndex;
      _lineStartOffset = _getLineStart(
        lineIndex: _lineIndex,
        currentOffset: _graphemeIndex,
      );
    } else {
      ++_columnIndex;
    }

    _skipCarriageReturn();

    if (_hasNext) return;

    /// We will not get a chance to buffer this last line. Also this iterator
    /// has no notion of trailing empty lines. A trailing line break will not
    /// trigger an empty line to be added to [_lines]
    _bufferCurrent();
    _markLineAsComplete();
  }

  @override
  int? peekNextChar() => _nextChar == -1 ? null : _nextChar;

  @override
  LineInfo get currentLineInfo => (
    start: _lineStartOffset,
    current: (
      lineIndex: _lineIndex,
      columnIndex: _columnIndex,
      utf16Index: _graphemeIndex,
    ),
  );

  @override
  List<Line> lines({int startIndex = 0}) =>
      UnmodifiableListView(_lines.skip(startIndex));

  /// Skips a `\r` if it's followed by a `\n`
  void _skipCarriageReturn() {
    /// From our point of view, we treat \r\n as a complete line break. We don't
    /// care if this isn't Windows. In our parsing context, we always fast
    /// forward this combination
    if (_currentChar == carriageReturn && _nextChar == lineFeed) {
      _currentChar = _nextChar;
      _hasNext = _iterator.moveNext();
      _nextChar = _iterator.current;
      ++_graphemeIndex;
      ++_columnIndex;
    }
  }

  /// Buffers the [_currentChar] if it is valid and not `\r` or `\n`
  void _bufferCurrent() {
    if (_currentChar == -1 || _currentChar.isLineBreak()) return;
    _bufferedRunes.add(_currentChar);
  }

  /// Buffers the current line's information to [_lines].
  void _markLineAsComplete() {
    _lines.add((
      startIndex: _lineStartOffset.utf16Index,
      inclusiveEndIndex: _graphemeIndex,
      chars: UnmodifiableListView(_bufferedRunes),
    ));

    _bufferedRunes = [];
  }
}
