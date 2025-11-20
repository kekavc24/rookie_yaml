import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/parser_state.dart';
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

typedef _Property = ({ParsedProperty property, NodeKind kind});

typedef ConcreteProperty = ({
  ParserEvent event,
  NodeKind kind,
  ParsedProperty property,
});

/// Parses node properties of flow node if [isBlockContext] is `false`.
///
/// When [isBlockContext] is `true`, the function gladly checks if a duplicate
/// node property was declared on a new line. In such a case, this means that
/// the property may belong to a node other than current one.
///
/// The function always exits when the first non-whitespace char declared on a
/// new line has a lesser indent than [minIndent]. [onParseComment] adds
/// comments encountered when skipping to the next parsable char declared on a
/// new line.
_Property _corePropertyParser(
  GraphemeScanner scanner, {
  required int minIndent,
  required TagResolver resolver,
  required void Function(YamlComment comment) onParseComment,
  required bool isBlockContext,
}) {
  final startOffset = scanner.lineInfo().current;

  var nodeKind = NodeKind.unknown;

  String? nodeAnchor;
  ResolvedTag? nodeTag;
  String? nodeAlias;
  int? indentOnExit;

  var lfCount = 0;

  bool isMultiline() => lfCount > 0;

  void skipAndTrackLF() {
    indentOnExit = skipToParsableChar(scanner, onParseComment: onParseComment);
    if (indentOnExit != null) ++lfCount;
  }

  void resetIndent() => indentOnExit = null;

  _Property exitIfBlock(String error) {
    /// Block node can have a lifeline in cases where a node spans multiple
    /// lines. The properties may belong to a
    if (isBlockContext && indentOnExit != null) {
      return (
        kind: nodeKind,
        property: NodeProperty(
          startOffset,
          scanner.lineInfo().start,
          indentOnExit,
          spanMultipleLines: true, // Obviously :)
          anchor: nodeAnchor,
          tag: nodeTag,
        ),
      );
    }

    throwWithRangedOffset(
      scanner,
      message: error,
      start: startOffset,
      end: scanner.lineInfo().current,
    );
  }

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
        }

      case lineFeed || carriageReturn || comment:
        {
          skipAndTrackLF();

          final hasNoIndent = indentOnExit == null;

          if (hasNoIndent || indentOnExit! < minIndent) {
            final (:start, :current) = scanner.lineInfo();

            return (
              kind: nodeKind,
              property: ParsedProperty.of(
                start,
                hasNoIndent ? current : start,
                spanMultipleLines: isMultiline(),
                indentOnExit: indentOnExit,
                anchor: nodeAnchor,
                tag: nodeTag,
              ),
            );
          }
        }

      case tag:
        {
          if (nodeTag != null) {
            return exitIfBlock(
              'A node can only have a single tag property',
            );
          } else if (scanner.charAfter == verbatimStart) {
            nodeTag = parseVerbatimTag(scanner);
          } else {
            final tagStart = scanner.lineInfo().current;
            final shorthand = parseTagShorthand(scanner);
            final (:kind, :tag) = resolver(
              tagStart,
              scanner.lineInfo().current,
              shorthand,
            );
            nodeKind = kind;
            nodeTag = tag;
          }

          resetIndent();
        }

      case anchor:
        {
          if (nodeAnchor != null) {
            return exitIfBlock('A node can only have a single anchor property');
          }

          scanner.skipCharAtCursor();
          nodeAnchor = parseAnchorOrAliasTrailer(scanner);

          resetIndent();
        }

      case alias:
        {
          if (nodeTag != null || nodeAnchor != null) {
            return exitIfBlock(
              'Alias nodes cannot have an anchor or tag property',
            );
          }

          scanner.skipCharAtCursor();
          nodeAlias = parseAnchorOrAliasTrailer(scanner);
          skipAndTrackLF();

          // Parsing an alias ignores any tag and anchor
          return (
            kind: NodeKind.unknown,
            property: Alias(
              startOffset,
              scanner.lineInfo().current,
              indentOnExit,
              alias: nodeAlias,
              spanMultipleLines: isMultiline(),
            ),
          );
        }

      // Exit immediately since we reached char that isn't a node property
      default:
        return (
          kind: nodeKind,
          property: ParsedProperty.of(
            startOffset,
            indentOnExit != null && indentOnExit! < minIndent
                ? scanner.lineInfo().start
                : scanner.lineInfo().current,
            spanMultipleLines: isMultiline(),
            indentOnExit: indentOnExit,
            anchor: nodeAnchor,
            tag: nodeTag,
          ),
        );
    }
  }

  /// Prefer having accurate indent info. Parsing only reaches here if we
  /// managed to parse both the tag and anchor.
  skipAndTrackLF();

  return (
    kind: nodeKind,
    property: ParsedProperty.of(
      startOffset,
      indentOnExit != null && indentOnExit! < minIndent
          ? scanner.lineInfo().start
          : scanner.lineInfo().current,
      spanMultipleLines: isMultiline(),
      indentOnExit: indentOnExit,
      anchor: nodeAnchor,
      tag: nodeTag,
    ),
  );
}

/// Parses node properties of a block node.
ConcreteProperty parseBlockProperties(
  GraphemeScanner scanner, {
  required int minIndent,
  required TagResolver resolver,
  required void Function(YamlComment comment) onParseComment,
}) {
  final (:property, :kind) = _corePropertyParser(
    scanner,
    minIndent: minIndent,
    resolver: resolver,
    onParseComment: onParseComment,
    isBlockContext: true,
  );

  return (
    kind: kind,
    property: property,
    event: inferNextEvent(
      scanner,
      isBlockContext: true,
      lastKeyWasJsonLike: false,
    ),
  );
}

/// Parses properties of a flow node and returns the next possible event after
/// all the properties have been parsed.
ConcreteProperty parseFlowProperties(
  GraphemeScanner scanner, {
  required int minIndent,
  required TagResolver resolver,
  required void Function(YamlComment comment) onParseComment,
  required bool lastKeyWasJsonLike,
}) {
  void throwIfLessIndent(int? currentIndent) {
    if (currentIndent != null && currentIndent < minIndent) {
      throwWithApproximateRange(
        scanner,
        message:
            'Expected at least $minIndent space(s). '
            'Found $currentIndent space(s)',
        current: scanner.lineInfo().current,
        charCountBefore: currentIndent,
      );
    }
  }

  // Move to the next parsable non-ws char
  throwIfLessIndent(
    skipToParsableChar(scanner, onParseComment: onParseComment),
  );

  // We can exit immediately if the next event is not a node property event
  if (inferNextEvent(
        scanner,
        isBlockContext: false,
        lastKeyWasJsonLike: lastKeyWasJsonLike,
      )
      case ParserEvent e when e is! NodePropertyEvent) {
    final offset = scanner.lineInfo().current;

    return (
      event: e,
      kind: NodeKind.unknown,
      property: ParsedProperty.empty(
        offset,
        offset,
        null,
        spanMultipleLines: false,
      ),
    );
  }

  final (:kind, :property) = _corePropertyParser(
    scanner,
    minIndent: minIndent,
    resolver: resolver,
    onParseComment: onParseComment,
    isBlockContext: false,
  );

  // Flow nodes are lax with indent. Never allow less than min indent.
  throwIfLessIndent(property.indentOnExit);

  return (
    event: inferNextEvent(
      scanner,
      isBlockContext: false,
      lastKeyWasJsonLike: lastKeyWasJsonLike,
    ),
    kind: kind,
    property: property,
  );
}
