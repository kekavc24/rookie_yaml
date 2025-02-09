import 'dart:math';

import 'package:characters/characters.dart';
import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';

part 'line_span.dart';

/// `start` to `end` index in string. Exclusive of the `end`.
typedef Offset = ({int start, int end});

///
typedef Predicate = bool Function(
  ReadableChar? previous,
  ReadableChar current,
);

typedef ChunkInfo = ({
  Offset offset,
  bool sourceEnded,
  bool lineEnded,
  ReadableChar? charOnExit,
});

void safeWriteChar(StringBuffer buffer, ReadableChar char) {
  buffer.write(isPrintable(char) ? char.string : char.raw);
}

final class ChunkScanner {
  ChunkScanner({
    required this.source,
  }) : _iterator = Characters(source).split(Characters(LineBreak.lf)).iterator {
    // We don't want chunks from empty lines
    if (source.isEmpty) return;
    _hasMoreLines = _iterator.moveNext();
  }

  int _currentOffset = -1;

  final String source;
  final Iterator<Characters> _iterator;

  bool _hasMoreLines = false;

  bool get canChunkMore => _hasMoreLines || _currentLine != null;

  Offset _getOffset(StringBuffer buffer) =>
      (start: max(0, _currentOffset - buffer.length), end: _currentOffset + 1);

  int _lineIndex = -1;
  LineSpan? _currentLine;

  ReadableChar? _charBeforeExit;

  ReadableChar? _charOnLastExit;

  /// Peeks the last char preceding the character that triggered the last
  /// [bufferChunk] call to exit.
  ///
  /// Usually this character, if not null, is already written to the buffer
  /// provided when calling [bufferChunk].
  ///
  /// If called after [skipCharAtCursor], then this is the last character
  /// the cursor pointed to before skipping.
  ReadableChar? get charBeforeCursor => _charBeforeExit;

  ReadableChar? get charAtCursor => _charOnLastExit;

  /// Peeks the next char after the character that triggered the last
  /// [bufferChunk] call to exit
  ReadableChar? peekCharAfterCursor() {
    // We prefetch next line if null
    if (_currentLine == null) {
      _fetchNextLine();
    }

    return _currentLine?.peekNextChar?.character;
  }

  /// Skips the current character that has not been read by this [ChunkScanner]
  /// but may have been accessed via [peekCharAfterCursor].
  ///
  /// This call is similar to a [bufferChunk] but just moves the cursor forward
  /// without accessing the value.
  ///
  /// Returns `true` if a character was skipped. Otherwise, `false`.
  (bool didSkip, ReadableChar? oldCharAtCursor) skipCharAtCursor() {
    var didSkip = false;

    if (peekCharAfterCursor() case final ReadableChar maybeNext) {
      _charBeforeExit = _charOnLastExit;
      _charOnLastExit = maybeNext;
      ++_currentOffset;

      if (_currentLine!.nextChar().isLastChar) {
        // Allows the next call to this scanner to fetch the next line
        // if available.
        _currentLine = null;
      }

      didSkip = true;
    } else if (_charOnLastExit != null) {
      _charBeforeExit = _charOnLastExit;
      _charOnLastExit = null; // No more characters to read
      _currentLine = null;
    }

    return (didSkip, _charBeforeExit);
  }

  /// Skips any whitespace and returns the [WhiteSpace] characters skipped.
  ///
  /// If [skipTabs] is `true`, then `\t` will also be skipped.
  ///
  /// `YAML` advises `\t` is only used for separation but not indentation
  /// which exclusively depends on white space.
  List<WhiteSpace> skipWhitespace({
    bool skipTabs = false,
    int? max,
    List<WhiteSpace> previouslyRead = const [],
  }) {
    final buffer = <WhiteSpace>[...previouslyRead];
    final hasMax = max != null;

    ReadableChar? char;

    while ((char = peekCharAfterCursor()) != null) {
      if (char is! WhiteSpace ||
          (hasMax && buffer.length >= max) ||
          (!skipTabs && char == WhiteSpace.tab)) {
        break;
      }

      buffer.add(char);
      skipCharAtCursor();
    }

    return buffer;
  }

  /// Reads and buffers all characters that fail the [exitIf] predicate or
  /// until the end of the current line, that is, until the line's
  /// [LineBreak.lineFeed] is emitted and no more characters are present in the
  /// line. Whichever condition comes first.
  ///
  /// See [ChunkInfo].
  ChunkInfo bufferChunk(StringBuffer buffer, {required Predicate exitIf}) {
    // Fetch next line if not present
    if (_currentLine == null) {
      // We exit and emit current offset
      if (!_hasMoreLines) {
        return (
          offset: _getOffset(buffer),
          sourceEnded: true,
          lineEnded: true,
          charOnExit: null,
        );
      }

      _fetchNextLine();
    }

    LineSpanChar? lastSpanChar;
    ReadableChar? maybeCharOnExit;

    final nonNullLine = _currentLine!; // Not null at this point.

    // Iterate as long as we can buffer characters
    while (nonNullLine.hasMoreChars) {
      final lineChar = nonNullLine.nextChar();

      // TODO: Reporter can access line info here
      lastSpanChar = lineChar;
      final LineSpanChar(character: current) = lineChar;

      // Fallback to last char before this run always on the first run
      _charBeforeExit = maybeCharOnExit ?? _charOnLastExit;
      maybeCharOnExit = current;
      ++_currentOffset;

      if (exitIf(_charBeforeExit, maybeCharOnExit)) {
        break;
      }

      safeWriteChar(buffer, current);
    }

    /// Revert to null if we created chunks till the end of the line. Helps
    /// guarantee the next line will be loaded if a chunk is requested
    if ((lastSpanChar?.isLastChar ?? true) || !nonNullLine.hasMoreChars) {
      _currentLine = null;
    }

    // Possible if we never iterated the loop!
    _charOnLastExit = maybeCharOnExit ?? _charOnLastExit;

    final offset = _getOffset(buffer);
    return (
      offset: offset,
      sourceEnded: !_hasMoreLines && offset.end >= source.length,
      lineEnded: _currentLine == null,
      charOnExit: maybeCharOnExit,
    );
  }

  void _fetchNextLine() {
    if (_hasMoreLines) {
      // Fetch next full non-iterated line
      final charIterable = _iterator.current;
      _hasMoreLines = _iterator.moveNext();

      _currentLine = LineSpan(
        lineIndex: ++_lineIndex,
        hasLineBreak: _hasMoreLines,
        startOffset: _currentOffset,
        characters: charIterable,
      );
    }
  }
}
