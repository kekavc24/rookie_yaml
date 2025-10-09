import 'dart:math';

import 'package:rookie_yaml/src/dumping/dumping.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';

part 'character_encoding.dart';
part 'encoding_utils.dart';
part 'error_utils.dart';

/// Represents information returned after a call to `bufferChunk` method
/// of the [GraphemeScanner]
///
/// `sourceEnded` - indicates if the entire string source was scanned.
///
/// `lineEnded` - indicates if an entire line was scanned, that is, until a
/// line feed was encountered.
///
/// `charOnExit` - indicates the character that triggered the `bufferChunk`
/// exit. Typically, the current character when `GraphemeScanner.charAtCursor`
/// is called.
typedef ChunkInfo = ({bool sourceEnded, int? charOnExit});

extension type _SafeChar(int value) {
  int? get char => value == -1 ? null : value;
}

/// Represents a scanner that iterates over a source only when a chunk or a
/// single character is requested
final class GraphemeScanner {
  GraphemeScanner(this._iterator)
    : _currentChar = _SafeChar(_iterator.current).char;

  GraphemeScanner.of(String source) : this(UnicodeIterator.ofString(source));

  /// Char iterator
  final SourceIterator _iterator;

  /// Checks if this scanner produce more characters based on the iteration
  /// state.
  ///
  /// `[NOTE]`: If [charAtCursor] is not `null`, then this will always return
  /// `true` even if no more lines are present. This is intentional. Any
  /// callers reading the [charAtCursor] must explicitly skip it if the code
  /// heavily depends on the correctness of this condition!
  bool get canChunkMore => _iterator.hasNext || _currentChar != null;

  /// Character before the cursor
  int? _charBefore;

  /// Character at the cursor
  int? _currentChar;

  /// Returns the current offset of this scanner and the actual start offset of
  /// the current [LineSpan].
  LineInfo lineInfo() => _iterator.currentLineInfo;

  /// Peeks the last char preceding the character that triggered the last
  /// [bufferChunk] call to exit.
  ///
  /// If called after [skipCharAtCursor], then this is the last character
  /// the cursor pointed to before skipping.
  int? get charBeforeCursor => _charBefore;

  /// Returns the current character at the cursor
  int? get charAtCursor => _currentChar;

  int? get charAfter => _iterator.peekNextChar();

  /// Skips the current character that has not been read by this
  /// [GraphemeScanner] but may have been accessed via [peekCharAfterCursor].
  ///
  /// This call is similar to a [bufferChunk] but just moves the cursor forward
  /// without accessing the value.
  ///
  /// Returns `true` if a character was skipped. Otherwise, `false`.
  (bool didSkip, int? oldCharAtCursor) skipCharAtCursor() {
    var didSkip = false;

    if (charAfter case final int maybeNext) {
      _charBefore = _currentChar;
      _currentChar = maybeNext;
      _iterator.nextChar();

      didSkip = true;
    } else if (_currentChar case int char) {
      _charBefore = _SafeChar(char).char;
      _currentChar = null; // No more characters to read
    }

    return (didSkip, _charBefore);
  }

  /// Skips any whitespace and returns the [WhiteSpace] characters skipped. If
  /// [skipTabs] is `true`, then tabs `\t` will also be skipped.
  ///
  /// [previouslyRead] must be mutable.
  List<int> skipWhitespace({
    bool skipTabs = false,
    int? max,
    List<int>? previouslyRead,
  }) {
    final buffer = previouslyRead ?? [];
    final hasMax = max != null;

    bool isMatch(int char) => skipTabs ? char.isWhiteSpace() : char.isIndent();

    while (charAfter != null &&
        !(hasMax && buffer.length >= max) &&
        isMatch(charAfter!)) {
      buffer.add(charAfter!);
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
    required T Function(int char) mapper,
    required void Function(T mapped) onMapped,
    required bool Function(int count, int possibleNext) stopIf,
  }) {
    var taken = 0;

    void incrementCount() => ++taken;

    if (includeCharAtCursor && _currentChar != null) {
      onMapped(mapper(_currentChar!));
      incrementCount();
    }

    while (canChunkMore) {
      /// May seem useless with the [canChunkMore] condition above but we need
      /// to leave scanner in a safe state. We read the char at cursor already!
      if (charAfter != null) {
        if (stopIf(taken, charAfter!)) {
          break;
        }

        onMapped(mapper(charAfter!));
        incrementCount();
      }

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
    void Function(int char) buffer, {
    required bool Function(int? previous, int current) exitIf,
  }) {
    int? maybeCharOnExit;
    var evalChatArCursor = false;

    // Iterate as long as we can buffer characters
    while (_iterator.hasNext) {
      _iterator.nextChar();

      // Fallback to last char before this run always on the first run
      _charBefore = maybeCharOnExit ?? _currentChar;
      maybeCharOnExit = _iterator.current;

      if (exitIf(_charBefore, maybeCharOnExit)) {
        evalChatArCursor = true;
        break;
      }

      buffer(maybeCharOnExit);
    }

    // Possible if we never iterated the loop!
    _currentChar = maybeCharOnExit ?? _currentChar;

    final sourceEnded = !evalChatArCursor && !_iterator.hasNext;

    if (sourceEnded) {
      skipCharAtCursor();
    }

    return (
      sourceEnded: sourceEnded,
      charOnExit: maybeCharOnExit,
    );
  }
}
