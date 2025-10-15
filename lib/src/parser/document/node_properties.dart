import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';

/// A node's parsed property.
sealed class ParsedProperty {
  ParsedProperty(
    RuneOffset start,
    RuneOffset end,
    this.indentOnExit, {
    required bool spanMultipleLines,
  }) : assert(
         end.utfOffset >= start.utfOffset,
         'Invalid start and end offset to a [ParsedProperty]',
       ),
       span = (start: start, end: end),
       isMultiline = spanMultipleLines || end.lineIndex > start.lineIndex;

  factory ParsedProperty.empty(
    RuneOffset start,
    RuneOffset end,
    int? indentOnExit, {
    required bool spanMultipleLines,
  }) = _Empty;

  /// Creates a wrapper that indicates the node's properties parsing call
  /// was just empty lines.
  factory ParsedProperty.of(
    RuneOffset start,
    RuneOffset end, {
    required bool spanMultipleLines,
    required int? indentOnExit,
    required String? anchor,
    required ResolvedTag? tag,
  }) {
    if (tag != null || anchor != null) {
      return NodeProperty(
        start,
        end,
        indentOnExit,
        spanMultipleLines: spanMultipleLines,
        anchor: anchor,
        tag: tag,
      );
    }

    return _Empty(
      start,
      end,
      indentOnExit,
      spanMultipleLines: spanMultipleLines,
    );
  }

  /// Returns a start [RuneOffset] (inclusive) and an end [RuneOffset]
  /// (exclusive).
  final RuneSpan span;

  /// The current indent after all the properties have been parsed.
  ///
  /// Will always be `null` if [isMultiline] is `false` or no more characters
  /// can be parsed.
  final int? indentOnExit;

  /// Returns `true` if any `tag`, `anchor` or `alias` was parsed. Otherwise,
  /// `false`.
  bool get parsedAny;

  /// Returns `true` if an `alias` was parsed. Otherwise, `false`.
  bool get isAlias => false;

  /// Returns `true` if a property spanned multiple lines.
  final bool isMultiline;
}

/// Empty node properties
final class _Empty extends ParsedProperty {
  _Empty(
    super.start,
    super.end,
    super.indentOnExit, {
    required super.spanMultipleLines,
  });

  @override
  bool get parsedAny => false;
}

/// Node `anchor` and/or `tag`.
final class NodeProperty extends ParsedProperty {
  NodeProperty(
    super.start,
    super.end,
    super.indentOnExit, {
    required super.spanMultipleLines,
    required this.anchor,
    required this.tag,
  });

  /// Node's anchor
  final String? anchor;

  /// Node's resolved tag
  final ResolvedTag? tag;

  @override
  bool get parsedAny => anchor != null || tag != null;
}

/// Node alias
final class Alias extends ParsedProperty {
  Alias(
    super.start,
    super.end,
    super.indentOnExit, {
    required super.spanMultipleLines,
    required this.alias,
  });

  /// Node being aliased
  final String alias;

  @override
  bool get parsedAny => true;

  @override
  bool get isAlias => true;
}

/// Parses the node properties of a `YamlSourceNode` and resolves any
/// [TagShorthand] parsed using the [resolver]. A [VerbatimTag] is never
/// resolved. All node properties declared on a new line must have an indent
/// equal to or greater than the [minIndent].
///
/// See `skipToParsableChar` which adds any comments parsed to [comments].
ParsedProperty parseNodeProperties(
  GraphemeScanner scanner, {
  required int minIndent,
  required ResolvedTag? Function(
    RuneOffset start,
    RuneOffset end,
    TagShorthand tag,
  )
  resolver,
  required List<YamlComment> comments,
}) {
  final propStart = scanner.lineInfo().current;

  String? nodeAnchor;
  ResolvedTag? nodeTag;
  String? nodeAlias;
  int? indentOnExit;

  var lfCount = 0;

  var lastWasLineBreak = false;

  void notLineBreak() => lastWasLineBreak = false;

  bool isMultiline() => lfCount > 0;

  int? skipAndTrackLF() {
    final indent = skipToParsableChar(scanner, comments: comments);
    if (indent != null) ++lfCount;
    return indent;
  }

  Never rangedThrow(String message) => throwWithRangedOffset(
    scanner,
    message: message,
    start: propStart,
    end: scanner.lineInfo().current,
  );

  /// A node can only have:
  ///   - Either a tag or anchor or both
  ///   - Alias only
  ///
  /// The two options above are mutually exclusive.
  while (scanner.canChunkMore && (nodeTag == null || nodeAnchor == null)) {
    switch (scanner.charAtCursor) {
      case space || tab:
        {
          scanner
            ..skipWhitespace(skipTabs: true) // Separation space
            ..skipCharAtCursor();

          notLineBreak();
        }

      case lineFeed || carriageReturn || comment:
        {
          indentOnExit = skipAndTrackLF();

          final hasNoIndent = indentOnExit == null;

          if (hasNoIndent || indentOnExit < minIndent) {
            final (:start, :current) = scanner.lineInfo();

            return ParsedProperty.of(
              propStart,
              hasNoIndent ? current : start,
              spanMultipleLines: isMultiline(),
              indentOnExit: indentOnExit,
              anchor: nodeAnchor,
              tag: nodeTag,
            );
          }

          lastWasLineBreak = true;
        }

      case tag:
        {
          if (nodeTag != null) {
            rangedThrow('A node can only have a single tag property');
          } else if (scanner.charAfter == verbatimStart) {
            nodeTag = parseVerbatimTag(scanner);
          } else {
            final tagStart = scanner.lineInfo().current;
            final shorthand = parseTagShorthand(scanner);
            nodeTag = resolver(tagStart, scanner.lineInfo().current, shorthand);
          }

          notLineBreak();
        }

      case anchor:
        {
          if (nodeAnchor != null) {
            rangedThrow('A node can only have a single anchor property');
          }

          scanner.skipCharAtCursor();
          nodeAnchor = parseAnchorOrAlias(scanner); // URI chars preceded by "&"

          notLineBreak();
        }

      case alias:
        {
          if (nodeTag != null || nodeAnchor != null) {
            rangedThrow('Alias nodes cannot have an anchor or tag property');
          }

          scanner.skipCharAtCursor();
          nodeAlias = parseAnchorOrAlias(scanner);
          indentOnExit = skipAndTrackLF();

          // Parsing an alias ignores any tag and anchor
          return Alias(
            propStart,
            scanner.lineInfo().current,
            indentOnExit,
            alias: nodeAlias,
            spanMultipleLines: isMultiline(),
          );
        }

      // Exit immediately since we reached char that isn't a node property
      default:
        return ParsedProperty.of(
          propStart,
          lastWasLineBreak && indentOnExit != null && indentOnExit < minIndent
              ? scanner.lineInfo().start
              : scanner.lineInfo().current,
          spanMultipleLines: isMultiline(),
          indentOnExit: lastWasLineBreak ? indentOnExit : null,
          anchor: nodeAnchor,
          tag: nodeTag,
        );
    }
  }

  /// Prefer having accurate indent info. Parsing only reaches here if we
  /// managed to parse both the tag and anchor.
  indentOnExit = skipAndTrackLF();

  return ParsedProperty.of(
    propStart,
    indentOnExit != null && indentOnExit < minIndent
        ? scanner.lineInfo().start
        : scanner.lineInfo().current,
    spanMultipleLines: isMultiline(),
    indentOnExit: indentOnExit,
    anchor: nodeAnchor,
    tag: nodeTag,
  );
}

typedef FlowNodeProperties = ({ParserEvent event, ParsedProperty property});

FlowNodeProperties parseSimpleFlowProps(
  GraphemeScanner scanner, {
  required int minIndent,
  required ResolvedTag? Function(
    RuneOffset start,
    RuneOffset end,
    TagShorthand tag,
  )
  resolver,
  required List<YamlComment> comments,
  bool lastKeyWasJsonLike = false,
}) {
  void throwHasLessIndent(int lessIndent) {
    throwWithApproximateRange(
      scanner,
      message:
          'Expected at least $minIndent space(s). '
          'Found $lessIndent space(s)',
      current: scanner.lineInfo().current,
      charCountBefore: lessIndent,
    );
  }

  if (skipToParsableChar(scanner, comments: comments) case int indent
      when indent < minIndent) {
    throwHasLessIndent(indent);
  }

  if (inferNextEvent(
        scanner,
        isBlockContext: false,
        lastKeyWasJsonLike: lastKeyWasJsonLike,
      )
      case ParserEvent e when e is! NodePropertyEvent) {
    final offset = scanner.lineInfo().current;

    return (
      event: e,
      property: ParsedProperty.empty(
        offset,
        offset,
        null,
        spanMultipleLines: false,
      ),
    );
  }

  final property = parseNodeProperties(
    scanner,
    minIndent: minIndent,
    resolver: resolver,
    comments: comments,
  );

  if (property case ParsedProperty(
    indentOnExit: int indent,
  ) when indent < minIndent) {
    throwHasLessIndent(indent);
  }

  return (
    event: inferNextEvent(
      scanner,
      isBlockContext: false,
      lastKeyWasJsonLike: lastKeyWasJsonLike,
    ),
    property: property,
  );
}
