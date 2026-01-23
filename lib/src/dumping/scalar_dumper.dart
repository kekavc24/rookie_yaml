import 'package:rookie_yaml/src/dumping/dumpable_node.dart';
import 'package:rookie_yaml/src/dumping/dumper_utils.dart';
import 'package:rookie_yaml/src/dumping/string_utils.dart';
import 'package:rookie_yaml/src/dumping/unfolding.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// A scalar dumped.
typedef DumpedScalar = ({
  bool isMultiline,
  int tentativeOffsetFromMargin,
  String node,
});

/// Joins the [lines] with a '\n`. All lines except the first line are also
/// indented accordingly.
DumpedScalar _dumped(
  Iterable<String> lines,
  int indent, {
  bool? isExplicit,
  bool isBlock = false,
}) {
  final indentation = ' ' * indent;
  final node = lines
      .take(1)
      .followedBy(lines.skip(1).map((l) => l.isEmpty ? l : '$indentation$l'))
      .join('\n');

  final dumpedAsExplicit =
      (isExplicit ?? lines.length > 1) || node.length > 1024;

  final offsetFromMargin = isBlock
      ? indent
      : indent +
            (dumpedAsExplicit ? lines.lastOrNull?.length ?? 0 : node.length);

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
        final (isDoubleQuoted, lines) = splitUnfoldScanned(
          object,
          forceInline: forceInline,
          isSingleQuoted: true,

          // Single quoted style only accepts printable chars
          scan: (_, _, current) => current.isPrintable(),
          unfolding: unfoldNormal,
        );

        return _dumped(quoted(lines, isDoubleQuoted ? '"' : "'"), indent);
      }

    case ScalarStyle.plain:
      {
        final (isDoubleQuoted, lines) = splitUnfoldScanned(
          object,
          forceInline: forceInline,
          isPlain: true,
          scan: (hasNext, previous, current) {
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

        final (isDoubleQuoted, lines) = splitUnfoldScanned(
          object,
          forceInline: forceInline,

          // Block styles only accept printable chars
          scan: (_, _, current) => current.isPrintable(),
          unfolding: (lines) {
            // Literal is canonically a restrictive WYSIWYG style.
            return isLiteral ? lines : unfoldBlockFolded(lines);
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
          return _dumped(
            [header(ChompingIndicator.strip), ''],
            indent,
            isExplicit: true,
            isBlock: true,
          );
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
          isExplicit: true,
          isBlock: true,
        );
      }
  }
}

/// A persistent dumper for scalars.
///
/// {@category dump_scalar}
final class ScalarDumper with PropertyDumper {
  const ScalarDumper._(
    this.defaultStyle,
    this.replaceEmpty,
    this.forceInline,
    this.onObject,
    this.asLocalTag,
  );

  /// Creates a [ScalarDumper].
  ///
  /// If [replaceEmpty] is true, empty strings are dumped as `null`.
  const ScalarDumper.fineGrained({
    required bool replaceEmpty,
    required Compose onScalar,
    required AsLocalTag asLocalTag,
    ScalarStyle style = ScalarStyle.doubleQuoted,
    bool forceInline = false,
  }) : this._(style, replaceEmpty, forceInline, onScalar, asLocalTag);

  /// Creates a [ScalarDumper] where empty strings are always dumped as `null`
  /// and aliases are compacted.
  const ScalarDumper.classic(
    Compose onScalar,
    AsLocalTag asLocalTag, [
    bool inline = false,
  ]) : this._(ScalarStyle.plain, true, inline, onScalar, asLocalTag);

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

  /// A helper function for composing a dumpable object.
  final Compose onObject;

  /// Tracks the object and its properties.
  final AsLocalTag asLocalTag;

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
    final nodeToDump = onObject(scalar);

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
      node: applyInline(asLocalTag(tag), anchor, node),
    );
  }
}
