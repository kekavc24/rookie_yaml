part of 'yaml_node.dart';

/// Represents a way to describe the amount of information to include in the
/// `YAML` source string.
enum DumpingStyle {
  /// Classic `YAML` output style. Parsed node properties (including global
  /// tags) are ignored. Aliases are unpacked and dumped asnthe actual node
  /// they reference.
  classic,

  /// Unlike [DumpingStyle.classic], this only works with any encountered
  /// [YamlSourceNode] which has properties. Anchors and aliases are preserved
  /// and all [TagShorthand]s are linked accurately to their respective
  /// [GlobalTag].
  compact,
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
  required String Function(bool isFirst, bool hasNext, String line) preflight,
  required bool Function(String previous, String current) isFolded,
}) sync* {
  final iterator = lines.iterator;
  var hasNext = false;

  void moveCursor() => hasNext = iterator.moveNext();

  /// Skips empty lines. This is a utility nested closure.
  /// `TIP`: Collapse it.
  (String? currentLine, List<String> buffered) skipEmpty(String current) {
    final buffer = [current];
    String? onExit;

    moveCursor();

    while (hasNext) {
      final line = iterator.current;

      if (line.isEmpty) {
        buffer.add(line);
        moveCursor();
        continue;
      }

      onExit = line;
      break;
    }

    return (onExit, buffer);
  }

  moveCursor(); // Start.

  var previous = iterator.current;

  moveCursor();
  yield preflight(true, hasNext, previous); // Emit first line always

  while (hasNext) {
    var current = iterator.current;

    // Eval with the last non-empty line if present
    final hasFoldTarget = isFolded(previous, current);

    if (current.isEmpty) {
      final (curr, buffered) = skipEmpty(current);

      yield* buffered;

      if (curr == null) {
        if (hasFoldTarget) yield _empty;
        break;
      }

      current = curr;
    }

    if (hasFoldTarget) {
      yield _empty;
    }

    moveCursor();

    yield preflight(false, hasNext, current);
    previous = current;
  }
}

/// Unfolds a previously folded string without modifying the state of the
/// current line being evaluated.
///
/// See [unfoldBlockFolded], [unfoldNormal].
Iterable<String> _unfoldNoPreflight(
  Iterable<String> lines, {
  required bool Function(String previous, String current) isFolded,
}) => _coreUnfolding(lines, preflight: (_, _, c) => c, isFolded: isFolded);

/// Unfolds [lines] to be encoded as [ScalarStyle.folded].
Iterable<String> unfoldBlockFolded(
  Iterable<String> lines,
) => _unfoldNoPreflight(
  lines,

  // Indented lines cannot be unfolded.
  isFolded: (previous, current) =>
      !previous.startsWith(' ') && !current.startsWith(' '),
);

/// Unfolds [lines] to be encoded as [ScalarStyle.plain] and
/// [ScalarStyle.singleQuoted]. These styles are usually folded without any
/// restrictions.
Iterable<String> unfoldNormal(Iterable<String> lines) => _unfoldNoPreflight(
  lines,
  isFolded: (_, _) => true,
);

/// Unfolds [lines] to be encoded as [ScalarStyle.doubleQuoted].
///
/// `YAML` allows linebreaks to be escaped in [ScalarStyle.doubleQuoted] if
/// you need trailing whitespace to be preserved. Leading whitespace can be
/// preserved if you escape the whitespace itself. A leading tab is
/// preserved in its raw form of `\` and `t`.
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
    return hasNext && current.endsWith(' ') || current.endsWith('\t')
        ? '$string$_slash\n'
        : string;
  },
  isFolded: (_, _) => true,
);
