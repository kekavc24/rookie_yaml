part of 'yaml_document.dart';

typedef _RootNodeInfo = ({
  bool foundDocEndMarkers,
  bool isBlockDoc,
  ParserDelegate rootDelegate,
});

/// Throws an exception if the prospective [Node] has an [indent] of `0`
/// (a child of the root node or the root node itself) and the document being
/// parsed did not have an explicit directives end marker (`---`) or the
/// directives end marker (`---`) is present but no directives were parsed.
///
/// While `YAML` insists that this must be true for all scalar types, this
/// method should only be called from block
void _throwIfUnsafeForDirectiveChar(
  ReadableChar? char, {
  required int indent,
  required bool isDocStartExplicit,
  required bool hasDirectives,
}) {
  if (char case Indicator.directive
      when indent == 0 && (!isDocStartExplicit || !hasDirectives)) {
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

ParserEvent _inferNextEvent(
  ChunkScanner scanner, {
  required bool isBlockContext,
  required bool lastKeyWasJsonLike,
  bool isRootCheck = false,
}) {
  final charAfter = scanner.peekCharAfterCursor();
  final nextIsSpace = charAfter == WhiteSpace.space;

  return switch (scanner.charAtCursor) {
    Indicator.doubleQuote => ScalarEvent.startFlowDoubleQuoted,
    Indicator.singleQuote => ScalarEvent.startFlowSingleQuoted,
    Indicator.literal => ScalarEvent.startBlockLiteral,
    Indicator.folded => ScalarEvent.startBlockFolded,

    Indicator.mappingValue when isBlockContext && nextIsSpace =>
      BlockCollectionEvent.startEntryValue,

    // Flow node doesn't need the space when key is json-like (double quoted)
    Indicator.mappingValue
        when !isBlockContext && (nextIsSpace || lastKeyWasJsonLike) =>
      FlowCollectionEvent.startEntryValue,

    Indicator.blockSequenceEntry when nextIsSpace && isBlockContext =>
      BlockCollectionEvent.startBlockListEntry,

    Indicator.mappingKey when isBlockContext && nextIsSpace =>
      BlockCollectionEvent.startExplicitKey,

    /// In flow collections, it is allow to occur separately without any key
    /// beside a "," or "{" or "}" or "[" or "]"
    Indicator.mappingKey
        when !isBlockContext &&
            (nextIsSpace || flowDelimiters.contains(charAfter)) =>
      FlowCollectionEvent.startExplicitKey,

    Indicator.flowSequenceStart => FlowCollectionEvent.startFlowSequence,
    Indicator.flowSequenceEnd => FlowCollectionEvent.endFlowSequence,
    Indicator.flowEntryEnd when !isRootCheck =>
      FlowCollectionEvent.nextFlowEntry,
    Indicator.mappingStart => FlowCollectionEvent.startFlowMap,
    Indicator.mappingEnd => FlowCollectionEvent.endFlowMap,

    Indicator.anchor => NodePropertyEvent.startAnchor,
    Indicator.alias => NodePropertyEvent.startAlias,
    Indicator.tag => NodePropertyEvent.startTag,

    _ => ScalarEvent.startFlowPlain,
  };
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

/// Parses a single node at the root of the document and throws an error if
/// the first node is not a [Scalar] while [rootInMarkerLine] is `true`. It
/// adds the current inferred [NodeParserEvent] to [parserEvents] and any
/// comment extracted before the root node was parsed.
///
/// [rootInMarkerLine] indicates whether the [Node] starts on the same line as
/// the directives end marker (`---`). If `true`, only a [Scalar] is expected.
/// Otherwise, throws an error.
_RootNodeInfo _parseNodeAtRoot(
  ChunkScanner scanner, {
  required bool rootInMarkerLine,
  required bool isDocStartExplicit,
  required bool hasDirectives,
  required List<ParserEvent> parserEvents,
  required SplayTreeSet<YamlComment> comments,
}) {
  const indentLevel = 0;
  final indent = _skipToParsableChar(scanner, comments: comments) ?? 0;

  _throwIfUnsafeForDirectiveChar(
    scanner.charAtCursor,
    indent: indent,
    isDocStartExplicit: isDocStartExplicit,
    hasDirectives: hasDirectives,
  );

  final event = _inferNextEvent(
    scanner,
    isBlockContext: true, // Always prefer block styling over flow
    lastKeyWasJsonLike: false,
    isRootCheck: true,
  );

  final offset = scanner.currentOffset;

  if (event is! ScalarEvent) {
    /// If the first node start on the same line as directives end marker,
    /// it must be a scalar
    if (rootInMarkerLine) {
      throw FormatException(
        'Only scalars are allowed to begin on the same line as directives '
        'end markers "---". Found: ${scanner.charAtCursor ?? ''}',
      );
    }

    var isBlockDoc = true;
    ParserDelegate? collectionDelegate;

    // Intentionally verbose
    switch (event) {
      case FlowCollectionEvent.endFlowMap ||
          FlowCollectionEvent.endFlowSequence:
        throw FormatException(
          'Leading closing "}" or "]" flow indicators found with no'
          ' opening "[" "{"',
        );

      case FlowCollectionEvent.startFlowMap:
        {
          collectionDelegate = MappingDelegate(
            collectionStyle: NodeStyle.flow,
            indentLevel: indentLevel,
            indent: indent,
            startOffset: offset,
            blockTags: {},
            inlineTags: {},
            blockAnchors: {},
            inlineAnchors: {},
          );

          parserEvents
            ..add(NodeEvent(event, collectionDelegate))
            ..add(FlowCollectionEvent.nextFlowEntry);

          isBlockDoc = false;
        }

      case FlowCollectionEvent.startFlowSequence:
        {
          collectionDelegate = SequenceDelegate(
            collectionStyle: NodeStyle.flow,
            indentLevel: indentLevel,
            indent: indent,
            startOffset: offset,
            blockTags: {},
            inlineTags: {},
            blockAnchors: {},
            inlineAnchors: {},
          );

          parserEvents
            ..add(NodeEvent(event, collectionDelegate))
            ..add(FlowCollectionEvent.nextFlowEntry);

          isBlockDoc = false;
        }

      case BlockCollectionEvent.startBlockListEntry:
        {
          collectionDelegate = SequenceDelegate(
            collectionStyle: NodeStyle.block,
            indentLevel: indentLevel,
            indent: indent,
            startOffset: offset,
            blockTags: {},
            inlineTags: {},
            blockAnchors: {},
            inlineAnchors: {},
          );

          parserEvents
            ..add(
              NodeEvent(
                BlockCollectionEvent.startBlockList,
                collectionDelegate,
              ),
            )
            ..add(event);
        }

      /// We treat all implicit block entries as part of a block map rather
      /// than a flow map
      default:
        {
          collectionDelegate = MappingDelegate(
            collectionStyle: NodeStyle.block,
            indentLevel: indentLevel,
            indent: indent,
            startOffset: offset,
            blockTags: {},
            inlineTags: {},
            blockAnchors: {},
            inlineAnchors: {},
          );

          parserEvents
            ..add(
              NodeEvent(
                BlockCollectionEvent.startBlockMap,
                collectionDelegate,
              ),
            )
            ..add(event);
        }
    }

    return (
      foundDocEndMarkers: false,
      isBlockDoc: isBlockDoc,
      rootDelegate: collectionDelegate,
    );
  }

  // Nothing else should be present
  final (isBlock, scalar) = switch (event) {
    ScalarEvent.startBlockLiteral || ScalarEvent.startBlockFolded => (
      true,
      parseBlockStyle(scanner, minimumIndent: indent),
    ),

    ScalarEvent.startFlowDoubleQuoted => (
      false,
      parseDoubleQuoted(scanner, indent: indent, isImplicit: false),
    ),

    ScalarEvent.startFlowSingleQuoted => (
      false,
      parseSingleQuoted(scanner, indent: indent, isImplicit: false),
    ),

    // We are aware of what character is at the start. Cannot be null
    _ => (
      true,
      parsePlain(
        scanner,
        indent: indent,
        charsOnGreedy: '',
        isImplicit: false,
      )!,
    ),
  };

  var foundDocEnd = scalar.hasDocEndMarkers;

  /// If inline with directives end markers or has any line breaks
  /// this scalar cannot be a key to a block map and defaults the document to
  /// having only a single top level scalar
  if (!foundDocEnd && (rootInMarkerLine || scalar.hasLineBreak)) {
    const exception = FormatException(
      'Expected a directives end marker "---" or document end marker "..." '
      'after parsing the root scalar',
    );

    final mayBeIndent = _skipToParsableChar(scanner, comments: comments);

    // It means a line break was encountered
    if (mayBeIndent != null) {
      throw exception;
    }

    /// For single quoted and double quoted, attempt to check for doc end
    /// markers. This also redeems block-like styles like plain, folded and
    /// literal which may have been exited due to a change in indent
    if (scanner.charAtCursor
        case Indicator.blockSequenceEntry || Indicator.period
        when hasDocumentMarkers(scanner, onMissing: (_) {})) {
      foundDocEnd = true;
    } else {
      throw exception;
    }
  }

  return (
    foundDocEndMarkers: foundDocEnd,
    isBlockDoc: isBlock,
    rootDelegate: ScalarDelegate(
      indentLevel: indentLevel,
      indent: indent,
      startOffset: offset,
      blockTags: {},
      inlineTags: {},
      blockAnchors: {},
      inlineAnchors: {},
    )..scalar = scalar,
  );
}

typedef _NodeProperties = ({
  int? indentOnExit,
  Set<ResolvedTag> blockTags,
  Set<ResolvedTag> inlineTags,
  Set<String> blockAnchors,
  Set<String> inlineAnchors,
  String? alias,
});

/// Parses the node properties of a [Node] and resolves any [LocalTag] parsed
/// using the [resolver]. A [VerbatimTag] is never resolved. All node
/// properties declared on a new line must have an indent equal to or greater
/// than the [minIndent].
///
/// See [_skipToParsableChar] which adds any comments parsed to [comments].
_NodeProperties _parseNodeProperties(
  ChunkScanner scanner, {
  required int minIndent,
  required ResolvedTag Function(LocalTag tag) resolver,
  required SplayTreeSet<YamlComment> comments,
}) {
  final blockTags = <ResolvedTag>{};
  final inlineTags = <ResolvedTag>{};
  final blockAnchors = <String>{};
  final inlineAnchors = <String>{};

  String? alias;
  int? indentOnExit;
  var lastWasLineBreak = false;

  /// Resets [lastWasLineBreak] to `false` if `true` and adds all [inline]
  /// elements to [block] since a new line was encountered and the properties
  /// are aligned in block with respect to where the node starts
  void resetIfLastWasLF<T>(
    T? object,
    Set<T> block,
    Set<T> inline, {
    bool forceReset = false,
  }) {
    if (lastWasLineBreak || forceReset) {
      lastWasLineBreak = false;
      block.addAll(inline);
      inline.clear();
    }

    if (object != null) inline.add(object);
  }

  parser:
  while (scanner.canChunkMore) {
    switch (scanner.charAtCursor) {
      /// Skip any separation space. This is only done if we are on the
      /// same line after parsing any node property. We assume it is content if
      /// we just inferred the indent.
      case WhiteSpace _ when !lastWasLineBreak:
        {
          scanner
            ..skipWhitespace(skipTabs: true)
            ..skipCharAtCursor();
        }

      // Node properties must be have the same/more indented than node
      case LineBreak _ || Indicator.comment:
        {
          indentOnExit = _skipToParsableChar(scanner, comments: comments);

          if (indentOnExit == null || indentOnExit < minIndent) {
            break parser;
          }

          lastWasLineBreak = true;
        }

      // Parse local tag or verbatim tag
      case Indicator.tag:
        {
          // Check if we are passing a verbatim tag
          ResolvedTag tag = switch (scanner.peekCharAfterCursor()) {
            ReadableChar next when next.string == verbatimStart.string =>
              parseVerbatimTag(scanner),

            _ => resolver(parseLocalTag(scanner)),
          };

          resetIfLastWasLF(tag, blockTags, inlineTags);
        }

      // Parse anchors
      case Indicator.anchor:
        {
          scanner.skipCharAtCursor();
          resetIfLastWasLF(
            parseAnchorOrAlias(scanner), // Parse remainining chars as URI chars
            blockAnchors,
            inlineAnchors,
          );
        }

      // Parsing an alias. Can never have more than one alias.
      case Indicator.alias:
        {
          if (alias != null) {
            throw FormatException(
              'The current node already declared an alias: "$alias". '
              'However another unexpected declaration has been found.',
            );
          }

          scanner.skipCharAtCursor();
          alias = parseAnchorOrAlias(scanner);

          final forceReset = lastWasLineBreak;
          resetIfLastWasLF(null, blockTags, inlineTags, forceReset: forceReset);
          resetIfLastWasLF(
            null,
            blockAnchors,
            inlineAnchors,
            forceReset: forceReset,
          );
        }

      default:
        break parser;
    }
  }

  return (
    indentOnExit: indentOnExit,
    blockTags: blockTags,
    inlineTags: inlineTags,
    blockAnchors: blockAnchors,
    inlineAnchors: inlineAnchors,
    alias: alias,
  );
}

/// Backtracks a [delegate]'s undirected graph until [matcher] returns `true`
/// or the current [ParserDelegate] is the root delegate (no parent). Returns
/// `null` only if the [delegate] passed in is `null`.
ParserDelegate? _backtrackDelegate(
  ParserDelegate? delegate, {
  required bool Function(ParserDelegate current) matcher,
}) {
  if (delegate == null) {
    return null;
  }

  var current = delegate;

  while (!matcher(current) || !current.isRootDelegate) {
    current = current.parent!;
  }

  return current;
}
