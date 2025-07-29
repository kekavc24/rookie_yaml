part of 'yaml_document.dart';

typedef _MapPreflightInfo = ({
  ParserEvent event,
  bool hasProperties,
  bool isExplicitEntry,
  bool blockMapContinue,
  int? indentOnExit,
});

typedef _ParseExplicitInfo = ({
  bool shouldExit,
  bool hasIndent,
  int? inferredIndent,
  _ParsedNodeProperties parsedNodeProperties,
  int laxIndent,
  int inlineIndent,
});

typedef _BlockNodeInfo = ({int? exitIndent, bool hasDocEndMarkers});

const _BlockNodeInfo _emptyScanner = (
  exitIndent: null,
  hasDocEndMarkers: false,
);

typedef _BlockNodeGeneric<T> = ({_BlockNodeInfo nodeInfo, T delegate});

typedef _BlockNode = _BlockNodeGeneric<ParserDelegate>;

typedef _BlockMapEntry = ({ParserDelegate? key, ParserDelegate? value});

typedef _BlockEntry = _BlockNodeGeneric<_BlockMapEntry>;

/// Throws an exception if the prospective [Node] has an [indent] of `0`
/// (a child of the root node or the root node itself) and the document being
/// parsed did not have an explicit directives end marker (`---`) or the
/// directives end marker (`---`) is present but no directives were parsed.
///
/// While `YAML` insists that this must be true for all scalar types, this
/// method should only be called from block
void _throwIfUnsafeForDirectiveChar(
  ReadableChar? char, {
  //required int indent,
  required bool isDocStartExplicit,
  required bool hasDirectives,
}) {
  if (char case Indicator.directive
      when (!isDocStartExplicit || !hasDirectives)) {
    throw FormatException(
      'Missing directives end marker "---" prevent the use of the directives '
      'indicator "%" at the start of a node',
    );
  }
}

/// Infers and returns `---` for a directive end marker and `...` for the
/// document end marker. Throws an exception if this could not be inferred
String _inferDocEndChars(ChunkScanner scanner) {
  final charToRepeat = switch (scanner.charBeforeCursor) {
    Indicator.blockSequenceEntry => "-",

    /// By default, the [hasDocumentMarkers] function attempts to greedily
    /// verify that there are no trailing characters after the document end
    /// marker `...` which YAML prohibits. We may be pointing to a `\n` at
    /// this point.
    ///
    /// `NB:` This is an assumption. All calls to this function must have a way
    /// to ensure the assumption about the `\n` made here is correct.
    Indicator.period || LineBreak? _ => ".",

    _ => throw FormatException(
      'Expected a single "-" for a directive end marker or "." for a '
      'document end marker. Alternatively, at least a line break or'
      ' nothing should be seen if no document end marker is inferred',
    ),
  };

  return charToRepeat.padRight(3, charToRepeat);
}

/// Returns `true` if the document starts on the same line as the directives
/// end marker (`---`) and must have a separation space between the last `-`
/// and the first valid document char. Throws an error if no separation space
/// is present, that is, a `\t` or whitespace.
///
/// `NOTE:` A document cannot start on the same line as document end marker
/// (`...`).
bool _docIsInMarkerLine(
  ChunkScanner scanner, {
  required bool isDocStartExplicit,
}) {
  if (!isDocStartExplicit) return false;

  switch (scanner.charAtCursor) {
    case WhiteSpace _:
      scanner.skipWhitespace(skipTabs: true);
      break;

    // When it is a line break or this is not the first doc and no
    case LineBreak? _:
      break;

    default:
      throw FormatException(
        'Expected a separation space after the directives end markers',
      );
  }

  if (scanner.charAtCursor is LineBreak?) {
    scanner.skipCharAtCursor();
    return false;
  }

  return true;
}

/// Skips any comments and linebreaks until a character that can be parsed
/// is encountered. Returns `null` if no indent was found.
///
/// Leading white spaces when this function is called are ignored. This
/// function treats them as separation space including tabs.
int? _skipToParsableChar(
  ChunkScanner scanner, {
  required SplayTreeSet<YamlComment> comments,
}) {
  int? indent;
  var isLeading = true;

  while (scanner.canChunkMore) {
    switch (scanner.charAtCursor) {
      /// If the first character is a leading whitespace, ignore. There
      /// is no need treating it as indent
      case WhiteSpace _ when isLeading:
        {
          scanner.skipWhitespace(skipTabs: true);
          scanner.skipCharAtCursor();
        }

      // Each line break triggers implicit indent inference
      case LineBreak lineBreak:
        {
          skipCrIfPossible(lineBreak, scanner: scanner);

          // Only spaces. Tabs are not considered indent
          indent = scanner.skipWhitespace().length;
          scanner.skipCharAtCursor();
          isLeading = false;
        }

      case Indicator.comment:
        {
          final (:onExit, :comment) = parseComment(scanner);
          comments.add(comment);

          if (onExit.sourceEnded) return null;
          indent = null; // Guarantees a recheck to indent
        }

      // We found the first parsable character
      default:
        return indent;
    }
  }

  return indent;
}

typedef _ParsedNodeProperties = ({
  int? indentOnExit,
  bool isMultiline,
  NodeProperties properties,
});

extension on _ParsedNodeProperties? {
  /// Returns `true` if any properties were parsed
  bool get parsedAny {
    if (this == null) return false;

    final NodeProperties(:isAlias, :parsedAnchorOrTag) = this!.properties;
    return isAlias || parsedAnchorOrTag;
  }
}

extension on NodeProperties {
  /// Returns `true` if any tag and/or anchor is parsed.
  bool get parsedAnchorOrTag => this.anchor != null || this.tag != null;

  /// Returns `true` if only an alias was parsed
  bool get isAlias => this.alias != null;
}

typedef NodeProperties = ({String? anchor, ResolvedTag? tag, String? alias});

/// Parses the node properties of a [Node] and resolves any [LocalTag] parsed
/// using the [resolver]. A [VerbatimTag] is never resolved. All node
/// properties declared on a new line must have an indent equal to or greater
/// than the [minIndent].
///
/// See [_skipToParsableChar] which adds any comments parsed to [comments].
_ParsedNodeProperties _parseNodeProperties(
  ChunkScanner scanner, {
  required int minIndent,
  required ResolvedTag Function(LocalTag tag) resolver,
  required SplayTreeSet<YamlComment> comments,
}) {
  String? anchor;
  ResolvedTag? tag;
  String? alias;
  int? indentOnExit;

  var lfCount = 0;

  var lastWasLineBreak = false;

  void notLineBreak() => lastWasLineBreak = false;

  bool isMultiline() => lfCount > 0;

  int? skipAndTrackLF() {
    final indentOnExit = _skipToParsableChar(scanner, comments: comments);
    ++lfCount;
    return indentOnExit;
  }

  /// A node can only have:
  ///   - Either a tag or anchor or both
  ///   - Alias only
  ///
  /// The two options above are mutually exclusive.
  while (scanner.canChunkMore && (tag == null || anchor == null)) {
    switch (scanner.charAtCursor) {
      case WhiteSpace _:
        {
          scanner
            ..skipWhitespace(skipTabs: true) // Separation space
            ..skipCharAtCursor();

          notLineBreak();
        }

      case LineBreak _ || Indicator.comment:
        {
          indentOnExit = skipAndTrackLF();

          if (indentOnExit == null || indentOnExit < minIndent) {
            return (
              properties: (alias: alias, anchor: anchor, tag: tag),
              indentOnExit: indentOnExit,
              isMultiline: true, // We know it is. Comments included ;)
            );
          }

          lastWasLineBreak = true;
        }

      case Indicator.tag:
        {
          if (tag != null) {
            throw FormatException('A node can only have a single tag property');
          }

          tag = switch (scanner.peekCharAfterCursor()) {
            ReadableChar next when next.string == verbatimStart.string =>
              parseVerbatimTag(scanner),

            _ => resolver(parseLocalTag(scanner)),
          };

          notLineBreak();
        }

      case Indicator.anchor:
        {
          if (anchor != null) {
            throw FormatException(
              'A node can only have a single anchor property',
            );
          }

          scanner.skipCharAtCursor();
          anchor = parseAnchorOrAlias(scanner); // URI chars preceded by "&"

          notLineBreak();
        }

      case Indicator.alias:
        {
          if (tag != null || anchor != null) {
            throw FormatException(
              'Alias nodes cannot have an anchor or tag property',
            );
          }

          scanner.skipCharAtCursor();

          // Parsing an alias ignores any tag and anchor
          return (
            properties: (
              alias: parseAnchorOrAlias(scanner),
              anchor: null,
              tag: null,
            ),
            indentOnExit: _skipToParsableChar(scanner, comments: comments),
            isMultiline: isMultiline(),
          );
        }

      // Exit immediately since we reached char that isn't a node property
      default:
        return (
          properties: (alias: alias, anchor: anchor, tag: tag),
          indentOnExit: lastWasLineBreak ? indentOnExit : null,
          isMultiline: isMultiline(),
        );
    }
  }

  return (
    properties: (alias: alias, anchor: anchor, tag: tag),

    /// Prefer having accurate indent info. Parsing only reaches here if we
    /// managed to parse both the tag and anchor.
    indentOnExit: skipAndTrackLF(),
    isMultiline: isMultiline(),
  );
}

typedef _FlowNodeProperties = ({
  ParserEvent event,
  bool hasMultilineProps,
  NodeProperties? properties,
});

_FlowNodeProperties _parseSimpleFlowProps(
  ChunkScanner scanner, {
  required int minIndent,
  required ResolvedTag Function(LocalTag tag) resolver,
  required SplayTreeSet<YamlComment> comments,
  bool lastKeyWasJsonLike = false,
}) {
  void throwHasLessIndent(int lessIndent) {
    throw FormatException(
      'Expected at ${minIndent - lessIndent} additional spaces but'
      ' found: ${scanner.charAtCursor}',
    );
  }

  if (_skipToParsableChar(scanner, comments: comments) case int indent
      when indent < minIndent) {
    throwHasLessIndent(indent);
  }

  if (_inferNextEvent(
        scanner,
        isBlockContext: false,
        lastKeyWasJsonLike: lastKeyWasJsonLike,
      )
      case ParserEvent e when e is! NodePropertyEvent) {
    return (event: e, properties: null, hasMultilineProps: false);
  }

  final (:indentOnExit, :isMultiline, :properties) = _parseNodeProperties(
    scanner,
    minIndent: minIndent,
    resolver: resolver,
    comments: comments,
  );

  if (indentOnExit != null && indentOnExit < minIndent) {
    throwHasLessIndent(indentOnExit);
  }

  return (
    properties: properties,
    hasMultilineProps: isMultiline,
    event: _inferNextEvent(
      scanner,
      isBlockContext: false,
      lastKeyWasJsonLike: lastKeyWasJsonLike,
    ),
  );
}

/// Updates the end offset of a [blockNode] (mapping/sequence) using its
/// undestructured [info]
void _blockNodeInfoEndOffset(
  ParserDelegate blockNode, {
  required ChunkScanner scanner,
  required _BlockNodeInfo info,
}) => _blockNodeEndOffset(
  blockNode,
  scanner: scanner,
  hasDocEndMarkers: info.hasDocEndMarkers,
  indentOnExit: info.exitIndent,
);

/// Updates the end offset of a [blockNode] (mapping/sequence) based on its
/// [indentOnExit]. If [hasDocEndMarkers] is `true`, the end offset is
/// the offset of the last `\n` (even if part of `\r\n`) before the
/// document end markers (`---` or `...`) `+1`.
void _blockNodeEndOffset(
  ParserDelegate blockNode, {
  required ChunkScanner scanner,
  required bool hasDocEndMarkers,
  required int? indentOnExit,
}) {
  if (!hasDocEndMarkers && indentOnExit == null) {
    if (!scanner.canChunkMore) {
      scanner.skipCharAtCursor(); // Completely skip last char
      blockNode.updateEndOffset = scanner.lineInfo().current;
      return;
    }

    throw ArgumentError.value(
      indentOnExit,
      'indentOnExit',
      'A block node always ends after an indent change but found null',
    );
  }

  // For both doc end chars and indent change. Reference start of line
  blockNode.updateEndOffset = scanner.lineInfo().start;
}
