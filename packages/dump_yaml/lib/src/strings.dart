import 'package:dump_yaml/src/unfolding.dart';
import 'package:rookie_yaml/rookie_yaml.dart';

extension Normalized on int {
  /// Normalizes all character that can be escaped.
  ///
  /// If [includeTab] is `true`, then `\t` is also normalized. If
  /// [includeLineBreaks] is `true`, both `\n` and `\r` are normalized. If
  /// [includeSlashes] is `true`, backslash `\` and slash `/` are escaped. If
  /// [includeDoubleQuote] is `true`, the double quote is escaped.
  Iterable<int> escapeYamlChar({
    required bool includeTab,
    required bool includeLineBreaks,
    bool includeSlashes = true,
    bool includeDoubleQuote = true,
  }) sync* {
    Iterable<int> out(int trailer, [bool escaped = true]) sync* {
      if (escaped) yield backSlash;
      yield trailer;
    }

    Iterable<int> lineBreaks(int ifEscaped) =>
        out(includeLineBreaks ? ifEscaped : this, includeLineBreaks);

    yield* switch (this) {
      unicodeNull => out(0x30),
      bell => out(0x61),
      asciiEscape => out(0x65),
      nextLine => out(0x4E),
      nbsp => out(0x5F),
      lineSeparator => out(0x4C),
      paragraphSeparator => out(0x50),
      backspace => out(0x62),
      verticalTab => out(0x76),
      formFeed => out(0x66),
      tab => out(includeTab ? 0x74 : tab, includeTab),
      lineFeed => lineBreaks(0x6E),
      carriageReturn => lineBreaks(0x66),
      backSlash || slash => out(this, includeSlashes),
      doubleQuote => out(this, includeDoubleQuote),
      _ => out(this, false),
    };
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
      code.escapeYamlChar(
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
    if (!iterator.moveNext() || iterator.current != lineFeed) {
      iterator.movePrevious();
      return;
    }
  }
}

/// Splits a string using its [iterator] as a YAML double quoted string with
/// the assumption that the [iterator]'s current code point is not invalid.
///
/// [buffered] and [lastLine] allow other styles to inject an [iterator] that
/// has been read to a N<sup>th</sup> position.
List<String> _splitAsYamlDoubleQuoted(
  RuneIterator iterator, {
  required bool forceInline,
  Iterable<String>? buffered,
  List<_WobblyChar>? lastLine,
}) {
  assert(iterator.current >= 0);
  final lines = <String>[];

  final buffer = StringBuffer(
    lastLine
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
        lastLine: currentLine,
      ),
    );
  }

  int? previous;
  var hasNext = false;
  void moveCursor(int? current) {
    previous = current;
    hasNext = iterator.moveNext();
  }

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

  moveCursor(null);

  while (hasNext) {
    final current = iterator.current;
    final splitLine = current.isLineBreak();

    // YAML's double quoted is the most lenient style.
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
  if (!iterator.moveNext()) return Iterable.empty();

  return unfoldDoubleQuoted(
    _splitAsYamlDoubleQuoted(iterator, forceInline: forceInline),
  );
}

/// Applies the [quotes] to the [lines] of a split string.
Iterable<String> asQuoted(Iterable<String> lines, [String quotes = '"']) sync* {
  if (lines.isEmpty) {
    yield '$quotes$quotes';
    return;
  }

  final leading = lines.first;

  if (lines.length == 1) {
    yield '$quotes$leading$quotes';
    return;
  }

  var linesToQuote = lines;

  void asLine(bool before, String? content, Iterable<String>? view) {
    final quoted = [content ?? quotes];
    final container = view ?? linesToQuote;

    linesToQuote = before
        ? quoted.followedBy(container)
        : (container).followedBy(quoted);
  }

  final (leadingContent, trailingView) = leading.isNotEmpty
      ? ('$quotes$leading', linesToQuote.skip(1))
      : (null, null);

  asLine(true, leadingContent, trailingView);

  final trailing = lines.last;

  final (trailingContent, leadingView) = trailing.isNotEmpty
      ? ('$trailing$quotes', linesToQuote.take(linesToQuote.length - 1))
      : (null, null);

  asLine(false, trailingContent, leadingView);
}
