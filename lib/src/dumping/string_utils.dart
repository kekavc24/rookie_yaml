import 'package:rookie_yaml/src/dumping/unfolding.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';

extension Normalizer on int {
  /// Normalizes all character that can be escaped.
  ///
  /// If [includeTab] is `true`, then `\t` is also normalized. If
  /// [includeLineBreaks] is `true`, both `\n` and `\r` are normalized. If
  /// [includeSlashes] is `true`, backslash `\` and slash `/` are escaped. If
  /// [includeDoubleQuote] is `true`, the double quote is escaped.
  Iterable<int> normalizeEscapedChars({
    required bool includeTab,
    required bool includeLineBreaks,
    bool includeSlashes = true,
    bool includeDoubleQuote = true,
  }) sync* {
    int? leader = backSlash;
    var trailer = this;

    switch (this) {
      case unicodeNull:
        trailer = 0x30;

      case bell:
        trailer = 0x61;

      case asciiEscape:
        trailer = 0x65;

      case nextLine:
        trailer = 0x4E;

      case nbsp:
        trailer = 0x5F;

      case lineSeparator:
        trailer = 0x4C;

      case paragraphSeparator:
        trailer = 0x50;

      case backspace:
        trailer = 0x62;

      case tab when includeTab:
        trailer = 0x74;

      case lineFeed when includeLineBreaks:
        trailer = 0x6E;

      case verticalTab:
        trailer = 0x76;

      case formFeed:
        trailer = 0x66;

      case carriageReturn when includeLineBreaks:
        trailer = 0x66;

      case backSlash || slash:
        {
          if (includeSlashes) break;
          leader = null;
        }

      case doubleQuote:
        {
          if (includeDoubleQuote) break;
          leader = null;
        }

      default:
        leader = null; // Remove nerf by default
    }

    if (leader != null) yield leader;
    yield trailer;
  }
}

extension type _WobblyChar(int code) {
  /// Normalizes a code point based on the style.
  ///
  /// If [isPlain] is `true`, all escaped characters (except `\t` and `\n`) are
  /// normalized. Slashes and double quotes are only escaped if [isDoubleQuoted]
  /// is `true`.
  ///
  /// If [isSingleQuoted] is `true`, all single quotes `'` are escaped as `''`.
  String safe({
    required bool forceInline,
    bool isPlain = false,
    bool isSingleQuoted = false,
    bool isDoubleQuoted = false,
  }) {
    if (isSingleQuoted && code == singleQuote) {
      return "''";
    } else if (!isPlain && !isDoubleQuoted) {
      return String.fromCharCode(code);
    }

    return String.fromCharCodes(
      code.normalizeEscapedChars(
        includeTab: false,
        includeLineBreaks: isDoubleQuoted && forceInline,
        includeSlashes: isDoubleQuoted,
        includeDoubleQuote: isDoubleQuoted,
      ),
    );
  }
}

/// Skips the `\r` only if the next char in the [iterator] is a `\n`.
void _skipCarriageReturn(
  int current, {
  required RuneIterator iterator,
  required bool hasNext,
}) {
  if (!hasNext) return;

  if (current == carriageReturn) {
    iterator.moveNext();

    if (iterator.current != lineFeed) {
      iterator.movePrevious();
      return;
    }
  }
}

/// Splits a string using its [iterator] as a YAML double quoted string with
/// the assumption that the [iterator]'s current code point is not invalid.
///
/// [buffered] and [currentLine] allow other styles to inject an [iterator]
/// that has been read to a N<sup>th</sup> position.
List<String> _splitAsYamlDoubleQuoted(
  RuneIterator iterator, {
  required bool forceInline,
  Iterable<String>? buffered,
  List<_WobblyChar>? currentLine,
}) {
  assert(iterator.current >= 0);
  final lines = <String>[];

  final buffer = StringBuffer(
    currentLine
            ?.map((c) => c.safe(forceInline: forceInline, isDoubleQuoted: true))
            .join() ??
        '',
  );

  int? previous;
  var hasNext = true;
  void moveCursor(int current) {
    previous = current;
    hasNext = iterator.moveNext();
  }

  void write(int code) {
    buffer.write(
      _WobblyChar(code).safe(forceInline: forceInline, isDoubleQuoted: true),
    );
  }

  void flush() {
    lines.add(buffer.toString());
    buffer.clear();
  }

  while (hasNext) {
    final current = iterator.current;

    if (!forceInline && current.isLineBreak()) {
      flush();
      _skipCarriageReturn(current, iterator: iterator, hasNext: hasNext);
    } else {
      write(current);
    }

    moveCursor(current);
  }

  if (buffer.isNotEmpty || (previous?.isLineBreak() ?? false)) {
    flush();
  }

  return buffered == null ? lines : buffered.followedBy(lines).toList();
}

/// Scans and unfolds a [string] using the [unfolding] function only if all its
/// code points pass the [scan] function provided. Degenerates to YAML's
/// double-quoted style if any code points fail the [scan] predicate.
///
/// If [isPlain] is `true`, all escaped characters (except `\t` and `\n`) are
/// normalized. Additional checks are defined in the [scan].
///
/// If [isSingleQuoted] is `true`, all single quotes `'` are escaped as `''`.
(bool failed, Iterable<String> unfoldedLines) splitUnfoldScanned(
  String string, {
  required bool forceInline,
  bool isSingleQuoted = false,
  bool isPlain = false,
  required bool Function(bool hasNext, int? previous, int current) scan,
  required Iterable<String> Function(Iterable<String> lines) unfolding,
}) {
  const naught = Iterable<_WobblyChar>.empty();
  final lines = <Iterable<_WobblyChar>>[];
  var currentLine = <_WobblyChar>[];
  final iterator = string.runes.iterator;

  /// Joins the chars of each line and applies the necessary formatting.
  Iterable<String> generic({bool isDoubleQuoted = false}) {
    return lines.map(
      (line) => line
          .map(
            (c) => c.safe(
              forceInline: forceInline,
              isPlain: isPlain && !isDoubleQuoted,
              isSingleQuoted: isSingleQuoted && !isDoubleQuoted,
              isDoubleQuoted: isDoubleQuoted,
            ),
          )
          .join(''),
    );
  }

  /// Degenerates to double quoted in the current state.
  Iterable<String> fallback() {
    return unfoldDoubleQuoted(
      _splitAsYamlDoubleQuoted(
        iterator,
        forceInline: forceInline,
        buffered: generic(isDoubleQuoted: true),
        currentLine: currentLine,
      ),
    );
  }

  int? previous;
  var hasNext = false;
  void moveCursor(int? current) {
    previous = current;
    hasNext = iterator.moveNext();
  }

  moveCursor(null);

  /// Adds the current line to the buffer only if it is not empty or [splitLine]
  /// is true.
  void flushLine({bool splitLine = true}) {
    if (currentLine.isNotEmpty) {
      lines.add(currentLine);
      currentLine = [];
    } else if (splitLine || (previous?.isLineBreak() ?? false)) {
      lines.add(naught);
    }
  }

  while (hasNext) {
    final current = iterator.current;
    final splitLine = current.isLineBreak();

    if ((forceInline && splitLine) || !scan(hasNext, previous, current)) {
      return (true, fallback());
    } else if (splitLine) {
      flushLine();
      _skipCarriageReturn(current, iterator: iterator, hasNext: hasNext);
    } else {
      currentLine.add(_WobblyChar(current));
    }

    moveCursor(current);
  }

  flushLine(splitLine: false);
  return (false, unfolding(generic()));
}

/// Splits and unfolds the [string] as a YAML double quoted string.
Iterable<String> splitUnfoldDoubleQuoted(String string, bool forceInline) {
  final iterator = string.runes.iterator;
  return iterator.moveNext()
      ? unfoldDoubleQuoted(
          _splitAsYamlDoubleQuoted(
            iterator,
            forceInline: forceInline,
          ),
        )
      : Iterable.empty();
}
