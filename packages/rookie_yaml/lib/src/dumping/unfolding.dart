import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

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
