import 'package:characters/characters.dart';
import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';

part 'line_span.dart';

/// Represents information returned after a call to `bufferChunk` method
/// of the [ChunkScanner]
///
/// `offset` - start to end of index in string source.
///
/// `sourceEnded` - indicates if the entire string source was scanned.
///
/// `lineEnded` - indicates if an entire line was scanned, that is, until a
/// line feed was encountered.
///
/// `charOnExit` - indicates the character that triggered the `bufferChunk`
/// exit. Typically, the current character when `ChunkScanner.charAtCursor`
/// is called.
typedef ChunkInfo = ({
  //Offset offset,
  bool sourceEnded,
  bool lineEnded,
  ReadableChar? charOnExit,
});

/// Checks if [char] is printable and writes it to the [buffer]. If not
/// printable, a sequence of raw representation of the character as UTF-16
/// escaped code units is written
void safeWriteChar(StringBuffer buffer, ReadableChar char) {
  buffer.write(isPrintable(char) ? char.string : char.raw);
}

/// Represents a scanner that iterates over a source only when a chunk or a
/// single character is requested
final class ChunkScanner {
  /// Initializes a [ChunkScanner] from a String [source].
  ChunkScanner._(this.source)
    : _iterator = Characters(source).split(Characters(LineBreak.lf)).iterator {
    // We don't want chunks from empty lines
    if (source.isEmpty) return;
    _hasMoreLines = _iterator.moveNext();
  }

  /// Initializes a [ChunkScanner] and moves character to first character
  factory ChunkScanner.of(String source) {
    final scanner = ChunkScanner._(source);
    scanner.skipCharAtCursor(); // Trigger a line fetch
    return scanner;
  }

  /// Current index of the scanner on the [source]
  int _currentOffset = -1;

  /// Source being iterated by this scanner.
  final String source;

  /// Represents a line iterator of the [source]
  final Iterator<Characters> _iterator;

  bool _hasMoreLines = false;

  /// Checks if this scanner produce more characters based on the iteration
  /// state
  bool get canChunkMore => _linesHaveChars || _charOnLastExit != null;

  bool get _linesHaveChars => _hasMoreLines || _currentLine != null;

  /// Index of current line being iterated
  int _lineIndex = -1;

  /// Current line whose characters are being iterated
  LineSpan? _currentLine;

  /// Character before the cursor
  ReadableChar? _charBeforeExit;

  /// Character at the cursor
  ReadableChar? _charOnLastExit;

  /// Current offset in source string with `0` being the start and
  /// `source.length - 1` being the end.
  int get currentOffset => _currentOffset;

  /// Peeks the last char preceding the character that triggered the last
  /// [bufferChunk] call to exit.
  ///
  /// If called after [skipCharAtCursor], then this is the last character
  /// the cursor pointed to before skipping.
  ReadableChar? get charBeforeCursor => _charBeforeExit;

  /// Returns the current character at the cursor
  ReadableChar? get charAtCursor => _charOnLastExit;

  /// Peeks the next char after the character present at [charAtCursor]
  ReadableChar? peekCharAfterCursor() {
    ReadableChar? next() => _currentLine?.peekNextChar?.character;

    var char = next();

    // We prefetch next line if null
    if (char == null && _linesHaveChars) {
      _fetchNextLine();
      char = next();
    }

    return char;
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

      final defLine = _currentLine!;

      if (defLine.nextChar().isLastChar || !defLine.hasMoreChars) {
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

  /// Skips any whitespace and returns the [WhiteSpace] characters skipped. If
  /// [skipTabs] is `true`, then tabs `\t` will also be skipped.
  ///
  /// [previouslyRead] must be mutable.
  List<ReadableChar> skipWhitespace({
    bool skipTabs = false,
    int? max,
    List<ReadableChar> previouslyRead = const [],
  }) {
    final buffer = previouslyRead;
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

  /// Returns the number of characters taken until a character failed the
  /// [stopIf] test, that is, evaluated to `false`.
  ///
  /// [includeCharAtCursor] adds the current character present when
  /// [charAtCursor] is called on the cursor only if it is not `null`. The
  /// [mapper] function is applied and value made available using [onMapped].
  int takeUntil<T>({
    required bool includeCharAtCursor,
    required T Function(ReadableChar char) mapper,
    required void Function(T mapped) onMapped,
    required bool Function(int count, ReadableChar possibleNext) stopIf,
  }) {
    var taken = 0;

    void incrementCount() => ++taken;

    if (includeCharAtCursor && _charOnLastExit != null) {
      onMapped(mapper(_charOnLastExit!));
      incrementCount();
    }

    while (canChunkMore) {
      final charAfter = peekCharAfterCursor()!;
      if (stopIf(taken, charAfter)) {
        break;
      }

      onMapped(mapper(charAfter));
      incrementCount();
      skipCharAtCursor();
    }

    return taken;
  }

  /// Reads and buffers all characters that fail the [exitIf] predicate or
  /// until the end of the current line, that is, until the line's
  /// [LineBreak.lineFeed] is emitted and no more characters are present in the
  /// line. Whichever condition comes first.
  ///
  /// See [ChunkInfo].
  ChunkInfo bufferChunk(
    void Function(ReadableChar char) buffer, {
    required bool Function(ReadableChar? previous, ReadableChar current) exitIf,
  }) {
    // Fetch next line if not present
    if (_currentLine == null) {
      // We exit and emit current offset
      if (!_hasMoreLines) {
        return (
          //offset: _getOffset(buffer),
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

      buffer(current);
    }

    /// Revert to null if we created chunks till the end of the line. Helps
    /// guarantee the next line will be loaded if a chunk is requested
    if ((lastSpanChar?.isLastChar ?? true) || !nonNullLine.hasMoreChars) {
      _currentLine = null;
    }

    // Possible if we never iterated the loop!
    _charOnLastExit = maybeCharOnExit ?? _charOnLastExit;

    //final offset = _getOffset(buffer);
    return (
      //offset: offset,
      sourceEnded: !_hasMoreLines && _currentOffset >= (source.length - 1),
      lineEnded: _currentLine == null,
      charOnExit: maybeCharOnExit,
    );
  }

  /// Fetches the next line in the line [_iterator] if any is present.
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
