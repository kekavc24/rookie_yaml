import 'package:rookie_yaml/src/dumping/dumpable_node.dart';
import 'package:rookie_yaml/src/dumping/string_utils.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// A scalar dumped.
typedef DumpedScalar = ({
  bool isMultiline,
  int tentativeOffsetFromMargin,
  String node,
});

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

/// Scans and unfolds a [string] using the [unfolding] function only if all its
/// code points pass the [tester] function provided. Degenerates to YAML's
/// double-quoted style if any code points fail the [tester] predicate.
///
/// If [isPlain] is `true`, all escaped characters (except `\t` and `\n`) are
/// normalized. Additional checks are defined in the [tester].
///
/// If [isSingleQuoted] is `true`, all single quotes `'` are escaped as `''`.
(bool failed, Iterable<String> unfoldedLines) unfoldScanned(
  String string, {
  required bool forceInline,
  bool isSingleQuoted = false,
  bool isPlain = false,
  required bool Function(bool hasNext, int? previous, int current) tester,
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

    if ((forceInline && splitLine) || !tester(hasNext, previous, current)) {
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

/// Joins the [lines] with a '\n`. All lines except the first line are also
/// indented accordingly.
DumpedScalar _dumped(Iterable<String> lines, int indent, [bool? isExplicit]) {
  final indentation = ' ' * indent;
  final node = lines
      .take(1)
      .followedBy(lines.skip(1).map((l) => l.isEmpty ? l : '$indentation$l'))
      .join('\n');

  final dumpedAsExplicit =
      (isExplicit ?? lines.length > 1) || node.length > 1024;

  final offsetFromMargin =
      indent + (dumpedAsExplicit ? lines.lastOrNull?.length ?? 0 : node.length);

  return (
    isMultiline: dumpedAsExplicit,
    node: node,
    tentativeOffsetFromMargin: offsetFromMargin,
  );
}

/// Dumps the [object] as a scalar.
///
/// The [object]'s [scalarStyle] is only respected if it conforms to the
/// restriction each [ScalarStyle] defines in the YAML spec. The [parentIndent]
/// is used by block styles to preserve any leading spaces (not tabs).
///
/// If the [object] has no characters, `null` will be returned only if use
/// [usePlainNull] is `true`. This may default to `null` anyway if the
/// [scalarStyle] provided is [ScalarStyle.plain]. Empty strings are not
/// allowed.
DumpedScalar _dumpScalar(
  String object, {
  required ScalarStyle scalarStyle,
  required int parentIndent,
  required int indent,
  required bool usePlainNull,
  required bool forceInline,
}) {
  if (object.isEmpty && (usePlainNull || scalarStyle == ScalarStyle.plain)) {
    return (
      isMultiline: false,
      tentativeOffsetFromMargin: indent + 4,
      node: 'null',
    );
  }

  Iterable<String> quoted(Iterable<String> lines, [String quotes = '"']) sync* {
    if (lines.isEmpty) {
      yield '$quotes$quotes';
      return;
    }

    var wrapped = lines;

    void asLine(bool before, String? content, Iterable<String>? view) {
      final val = [content ?? quotes];
      wrapped = before
          ? (val).followedBy(view ?? wrapped)
          : (view ?? wrapped).followedBy(val);
    }

    final first = lines.first;

    if (lines.length == 1) {
      yield '$quotes$first$quotes';
      return;
    }

    final (leadingContent, trailingView) = switch (first.isNotEmpty) {
      true => ('$quotes$first', wrapped.skip(1)),
      _ => (null, null),
    };

    asLine(true, leadingContent, trailingView);

    final last = lines.last;

    final (trailingContent, leadingView) = switch (last.isNotEmpty) {
      true => ('$last$quotes', wrapped.take(wrapped.length - 1)),
      _ => (null, null),
    };

    asLine(false, trailingContent, leadingView);
    yield* wrapped;
  }

  switch (scalarStyle) {
    case ScalarStyle.singleQuoted:
      {
        final (isDoubleQuoted, lines) = unfoldScanned(
          object,
          forceInline: forceInline,
          isSingleQuoted: true,

          // Single quoted style only accepts printable chars
          tester: (_, _, current) => current.isPrintable(),
          unfolding: unfoldNormal,
        );

        return _dumped(quoted(lines, isDoubleQuoted ? '"' : "'"), indent);
      }

    case ScalarStyle.plain:
      {
        final (isDoubleQuoted, lines) = unfoldScanned(
          object,
          forceInline: forceInline,
          isPlain: true,
          tester: (hasNext, previous, current) {
            if (!hasNext && (current.isLineBreak() || current.isWhiteSpace())) {
              return false;
            }

            return switch (previous) {
              // Cannot start plain with "#". That's just a comment.
              null ||
              space ||
              tab ||
              carriageReturn ||
              lineFeed when current == comment => false,

              // Not allowed by YAML.
              mappingKey ||
              mappingValue ||
              blockSequenceEntry when current.isWhiteSpace() => false,

              // Not safe in flow styles.
              _
                  when parentIndent == seamlessIndentMarker &&
                      current.isFlowDelimiter() =>
                false,

              _ => true,
            };
          },
          unfolding: unfoldNormal,
        );

        return _dumped(
          !isDoubleQuoted && lines.isNotEmpty ? lines : quoted(lines),
          indent,
        );
      }

    case ScalarStyle.doubleQuoted:
      return _dumped(
        quoted(splitUnfoldDoubleQuoted(object, forceInline)),
        indent,
      );

    // Block styles
    default:
      {
        final isLiteral = scalarStyle == ScalarStyle.literal;

        final (isDoubleQuoted, lines) = unfoldScanned(
          object,
          forceInline: forceInline,

          // Block styles only accept printable chars
          tester: (_, _, current) => current.isPrintable(),
          unfolding: (lines) {
            // Literal is canonically a restrictive WYSIWYG style.
            if (isLiteral) return lines;
            return unfoldBlockFolded(lines);
          },
        );

        if (isDoubleQuoted) {
          return _dumped(quoted(lines), indent);
        }

        var blockIndent = indent;
        int? indentationIndicator;

        String header(ChompingIndicator chomping) =>
            '${isLiteral ? '|' : '>'}'
            '${indentationIndicator ?? ''}${chomping.indicator}';

        final first = lines.firstOrNull;

        if (first == null || (first.isEmpty && lines.length == 1)) {
          return _dumped([header(ChompingIndicator.strip), ''], indent, true);
        } else if (first.startsWith(' ')) {
          // Block styles infer indent from the first non-empty line and ignore
          // any indentation recommendations by the parser. Force the node
          // inwards and use an indentation indicator.
          blockIndent = parentIndent + 1;
          indentationIndicator = 1;
        }

        return _dumped(
          [
            header(
              lines.last.isEmpty
                  ? ChompingIndicator.keep
                  : ChompingIndicator.strip,
            ),
          ].followedBy(isLiteral || first.isNotEmpty ? lines : lines.skip(1)),
          blockIndent,
          true,
        );
      }
  }
}

// TODO: Move dis!
// TODO: Validate props my guy
typedef PushProperties =
    String? Function(
      ResolvedTag? tag,
      String? anchor,
      ConcreteNode<Object?> object,
    );

/// A persistent dumper for scalars.
final class ScalarDumper {
  const ScalarDumper._(
    this.defaultStyle,
    this.replaceEmpty,
    this.forceInline,
    this.globals,
  );

  /// Creates a [ScalarDumper].
  ///
  /// If [replaceEmpty] is true, empty strings are dumped as `null`.
  const ScalarDumper.fineGrained({
    required bool replaceEmpty,
    required PushProperties pushProperties,
    ScalarStyle style = ScalarStyle.doubleQuoted,
    bool forceInline = false,
  }) : this._(style, replaceEmpty, forceInline, pushProperties);

  /// Creates a [ScalarDumper] where empty strings are always dumped as `null`
  /// and aliases are compacted.
  const ScalarDumper.classic(PushProperties push)
    : this._(ScalarStyle.doubleQuoted, true, false, push);

  /// Style to use when a block node is inserted into node
  final ScalarStyle defaultStyle;

  /// Whether empty strings are dumped as `null`.
  final bool replaceEmpty;

  /// Whether the scalar should be forced inline if a line break is seen.
  ///
  /// The dumper will prioritize respecting the style provided when [dump] is
  /// called or the [defaultStyle]. However, if not possible, degenerates to
  /// [ScalarStyle.doubleQuoted] and normalizes the line break.
  final bool forceInline;

  /// Tracks the object and its properties.
  final PushProperties globals;

  /// Dumps a [scalar].
  ///
  /// The [scalar] is always dumped as a flow node. Consider wrapping the
  /// [scalar] as a [DumpableNode] and overriding the [NodeStyle] if the [style]
  /// is a [ScalarStyle.folded] or [ScalarStyle.literal].
  DumpedScalar dump(
    Object? scalar, {
    required int indent,
    int parentIndent = 0,
    required ScalarStyle? style,
  }) {
    final nodeToDump = scalar is DumpableNode ? scalar : dumpableType(scalar);

    // Aliases here are returned "as-is".
    if (nodeToDump is DumpableAsAlias) {
      final alias = nodeToDump.dumpable;

      return (
        isMultiline: false,
        tentativeOffsetFromMargin: indent + alias.length,
        node: alias,
      );
    }

    final ConcreteNode(:dumpable, :anchor, :tag) =
        nodeToDump as ConcreteNode<Object?>;

    final localTag = globals(tag, anchor, nodeToDump);

    final (:isMultiline, :node, :tentativeOffsetFromMargin) = _dumpScalar(
      dumpable?.toString() ?? '',
      scalarStyle: style ?? defaultStyle,
      parentIndent: parentIndent,
      indent: indent,
      usePlainNull: replaceEmpty,
      forceInline: forceInline,
    );

    return (
      isMultiline: isMultiline,
      tentativeOffsetFromMargin: tentativeOffsetFromMargin,
      node: _applyProperties(localTag, anchor, node),
    );
  }

  /// Applies the scalar's properties inline.
  String _applyProperties(String? tag, String? anchor, String node) {
    var dumped = node;

    void apply(String? prop, [String prefix = '']) {
      if (prop == null) return;
      dumped = '$prefix$prop $dumped';
    }

    apply(tag);
    apply(anchor, '&');
    return dumped;
  }
}
