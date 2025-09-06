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

extension on int {
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
  yield yielder(true, hasNext, previous); // Emit first line always

  while (hasNext) {
    var current = iterator.current;

    // Eval with the last non-empty line if present
    final hasFoldTarget = canUnfold(previous, current);

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

    yield yielder(false, hasNext, current);
    previous = current;
  }
}

/// Unfolds [lines] to be encoded as [ScalarStyle.folded].
Iterable<String> unfoldBlockFolded(Iterable<String> lines) => _coreUnfolding(
  lines,

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

/// Joins [lines] of a scalar being dumped by applying the specified [indent]
/// to each line. If [includeFirst] is `true`, the first line is also indented.
(String joinIndent, String joined) _joinScalar(
  Iterable<String> lines, {
  required int indent,
  bool includeFirst = false,
}) {
  final joinIndent = ' ' * indent;
  return (
    joinIndent,
    lines
        .mapIndexed((i, l) => includeFirst || i != 0 ? '$joinIndent$l' : l)
        .join('\n'),
  );
}

/// Splits [blockContent] for a scalar to be encoded as [ScalarStyle.folded] or
/// [ScalarStyle.literal].
Iterable<String> _splitBlockString(String blockContent) => splitLazyChecked(
  blockContent,
  replacer: (index, char) sync* {
    if (!char.isPrintable()) {
      throw FormatException(
        'Non-printable character cannot be encoded as literal/folded',
        blockContent,
        index,
      );
    }

    yield char;
  },
  lineOnSplit: () {},
);

/// Encodes any [object] to valid `YAML` source string. If [jsonCompatible] is
/// `true`, the object is encoded as valid json with collections defaulting to
/// [NodeStyle.flow] and scalars encoded with [ScalarStyle.doubleQuoted].
///
/// In addition to encoding the [object], it returns if the source string can
/// be an explicit key in a `YAML` [Mapping] and if the [object] was a
/// collection.
///
/// The [object] is always an explicit key if it is a collection or was
/// [Scalar]-like and span multiple lines.
({bool explicitIfKey, String encoded}) _encodeObject<T>(
  T object, {
  required int indent,
  required bool jsonCompatible,
  required NodeStyle nodeStyle,
}) {
  final encodable = switch (object) {
    AliasNode(:final aliased) => aliased,
    _ => object,
  };

  switch (encodable) {
    case List list:
      return (
        explicitIfKey: true,
        encoded: dumpSequence(
          list,
          indent: indent,
          collectionNodeStyle: nodeStyle,
          jsonCompatible: jsonCompatible,
        ),
      );

    case Map map:
      return (
        explicitIfKey: true,
        encoded: dumpMapping(
          map,
          indent: indent,
          collectionNodeStyle: nodeStyle,
          jsonCompatible: jsonCompatible,
        ),
      );

    default:
      {
        final (:explicitIfKey, :encodedScalar) = dumpScalar(
          encodable,
          indent: indent,
          jsonCompatible: jsonCompatible,
          parentNodeStyle: nodeStyle,
        );

        return (
          explicitIfKey: explicitIfKey,
          encoded: encodedScalar,
        );
      }
  }
}

/// Replaces an empty [string] with an explicit `null`.
String _replaceIfEmpty(String string) => string.isEmpty ? 'null' : string;
