import 'package:rookie_yaml/src/scanner/source_iterator.dart';

/// Splits a string lazily at `\r` or `\n` or `\r\n` which are recognized as
/// line breaks in YAML.
///
/// Unlike [splitStringLazy], this function allows you to declare a [replacer]
/// for [Runes] being iterated. [lineOnSplit] callback is triggered everytime a
/// line is split after a `\r` or `\n` or `\r\n`. May be inaccurate.
Iterable<String> splitLazyChecked(
  String string, {
  required Iterable<int> Function(int offset, int charCode) replacer,
  required void Function() lineOnSplit,
}) => _coreLazySplit(string, replacer: replacer, lineOnSplit: lineOnSplit);

/// Splits a string lazily at `\r` or `\n` or `\r\n` which are recognized as
/// line breaks in YAML.
///
/// This function breaks the lines indiscriminately and does not track the
/// dominant line break based on the platform unless the `\r\n` is seen.
Iterable<String> splitStringLazy(String string) => _coreLazySplit(string);

/// Splits a string lazily at `\r` or `\n` or `\r\n` which are recognized as
/// line breaks in YAML.
///
/// Unlike [splitStringLazy], this function allows you to declare a [replacer]
/// for [Runes] being iterated. [lineOnSplit] callback is triggered everytime a
/// line is split after a `\r` or `\n` or `\r\n`. May be inaccurate.
Iterable<String> _coreLazySplit(
  String string, {
  Iterable<int> Function(int offset, int charCode)? replacer,
  void Function()? lineOnSplit,
}) sync* {
  final subchecker =
      replacer ??
      (_, c) sync* {
        yield c;
      };

  final splitCallback = lineOnSplit ?? () {};

  final runeIterator = string.runes.iterator;

  bool canIterate() => runeIterator.moveNext();

  final buffer = StringBuffer();
  int? previous; // Track trailing line breaks for preservation

  splitter:
  while (canIterate()) {
    var current = runeIterator.current;

    switch (current) {
      case carriageReturn:
        {
          // If just "\r", exit immediately without overwriting trailing "\r"
          if (!canIterate()) {
            splitCallback();
            yield buffer.toString();
            buffer.clear();
            break splitter;
          }

          current = runeIterator.current;
          continue gen; // Let "lf" handle this.
        }

      gen:
      case lineFeed:
        {
          splitCallback();

          yield buffer.toString();
          buffer.clear();

          // In case we got this char from the carriage return
          if (current != lineFeed && current != -1) {
            continue writer;
          }
        }

      writer:
      default:
        for (final char in subchecker(runeIterator.rawIndex, current)) {
          buffer.writeCharCode(char);
        }
    }

    previous = current;
  }

  // Ensure we flush all buffered contents. A trailing line break signals
  // we need it preserved. Thus, emit an empty string too in this case.
  if (buffer.isNotEmpty || previous == carriageReturn || previous == lineFeed) {
    yield buffer.toString();
  }
}

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

const _empty = '';
const _slash = r'\';
const _nerfedTab =
    '$_slash'
    't';

/// Unfolds a previously folded string. This is a generic unfolding
/// implementation that allows any [ScalarStyle] that is not
/// [ScalarStyle.literal] to unfold a previously folded string.
///
/// Each (foldable) [ScalarStyle] can specify a [preflight] callback that allows
/// the current line to be preprocessed before it is "yielded" and a [isFolded]
/// callback that evaluates if the `current` line can be folded based on the
/// state of the `previous` line.
///
/// [isFolded] usually evaluates to `true` for all [ScalarStyle] that can be
/// used in [NodeStyle.flow]. See [unfoldBlockFolded] for conditions that
/// result in this function to returning `true` in [ScalarStyle.folded].
///
/// [preflight] allows [ScalarStyle.doubleQuoted] to preprocess the current
/// line to ensure that it's state is preserved when it has leading and
/// trailing whitespace. See [unfoldDoubleQuoted].
///
/// See [unfoldNormal] for other [ScalarStyle]s.
Iterable<String> _coreUnfolding(
  Iterable<String> lines, {
  bool isBlockUnfolding = false,
  String Function(bool isFirst, bool hasNext, String line)? preflight,
  bool Function(String previous, String current)? isFolded,
}) sync* {
  final canUnfold = isFolded ?? (_, _) => true;
  final yielder = preflight ?? (_, _, line) => line;

  final iterator = lines.iterator;
  var hasNext = false;

  void moveCursor() => hasNext = iterator.moveNext();

  /// Skips empty lines. This is a utility nested closure.
  /// `TIP`: Collapse it.
  Iterable<String> skipEmpty(
    String current, {
    required void Function(String? current) onComplete,
  }) sync* {
    String? onExit;

    yield current;
    moveCursor();

    while (hasNext) {
      final line = iterator.current;

      if (line.isNotEmpty) {
        onExit = line;
        break;
      }

      yield line;
      moveCursor();
    }

    onComplete(onExit);
  }

  moveCursor(); // Start.

  var previous = iterator.current;

  moveCursor();
  yield yielder(true, hasNext, previous); // Emit first line always

  while (hasNext) {
    String? current = iterator.current;

    // Eval with the last non-empty line if present
    final hasFoldTarget = canUnfold(previous, current);

    if (current.isEmpty) {
      yield* skipEmpty(current, onComplete: (line) => current = line);

      if (current == null) {
        // Trailing line breaks are never folded, just chomped in block folded
        // scalars
        if (!isBlockUnfolding && hasFoldTarget) yield _empty;
        break;
      }
    }

    if (hasFoldTarget) {
      yield _empty;
    }

    moveCursor();

    yield yielder(false, hasNext, current!);
    previous = current!;
  }
}

/// Unfolds [lines] to be encoded as [ScalarStyle.folded].
Iterable<String> unfoldBlockFolded(Iterable<String> lines) => _coreUnfolding(
  lines,
  isBlockUnfolding: true,

  // Indented lines cannot be unfolded.
  isFolded: (previous, current) =>
      !previous.startsWith(' ') && !current.startsWith(' '),
);

/// Unfolds [lines] to be encoded as [ScalarStyle.plain] and
/// [ScalarStyle.singleQuoted]. These styles are usually folded without any
/// restrictions.
Iterable<String> unfoldNormal(Iterable<String> lines) => _coreUnfolding(lines);

/// Unfolds [lines] to be encoded as [ScalarStyle.doubleQuoted].
///
/// `YAML` allows linebreaks to be escaped in [ScalarStyle.doubleQuoted] if
/// you need trailing whitespace to be preserved. Leading whitespace can be
/// preserved if you escape the whitespace itself. A leading tab is preserved
/// in its raw form of `\` and `t`.
Iterable<String> unfoldDoubleQuoted(Iterable<String> lines) => _coreUnfolding(
  lines,
  preflight: (isFirst, hasNext, current) {
    var string = current;

    /// The first line cannot suffer from the truncated whitespace issue in flow
    /// scalars. Double quoted allows us to escape the whitespace itself. For
    /// tabs, we just "nerf" it since we have no line break to escape.
    ///
    /// This is only valid if we have more characters after the whitespace.
    if (!isFirst) {
      string = current.startsWith(' ')
          ? '$_slash$string'
          : current.startsWith('\t')
          ? '$_nerfedTab${string.substring(1)}'
          : string;

      /// Make string compact. We don't want to pollute it with additional
      /// trailing escaped linebreak when the leading whitespace is escaped/
      /// "nerfed"
      if (current.length == 1) return string;
    }

    // Escape the linebreak itself for trailing whitespace
    return hasNext && (current.endsWith(' ') || current.endsWith('\t'))
        ? '$string$_slash\n'
        : string;
  },
);
