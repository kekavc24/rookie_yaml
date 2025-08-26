part of 'yaml_document.dart';

/// A event that controls the [DocumentParser]'s next parse action
abstract interface class ParserEvent {
  /// Returns `true` if the [DocumentParser] is parsing a [Node] with
  /// [NodeStyle.flow] styling.
  bool get isFlowContext;
}

/// An event that triggers parsing of a [Scalar]
enum ScalarEvent implements ParserEvent {
  /// Parse a scalar with [ScalarStyle.literal]
  startBlockLiteral(isFlowContext: false),

  /// Parse a scalar with [ScalarStyle.folded]
  startBlockFolded(isFlowContext: false),

  /// Parse a scalar with [ScalarStyle.plain]
  startFlowPlain(isFlowContext: true),

  /// Parse a scalar with [ScalarStyle.doubleQuoted]
  startFlowDoubleQuoted(isFlowContext: true),

  /// Parse a scalar with [ScalarStyle.singleQuoted]
  startFlowSingleQuoted(isFlowContext: true);

  const ScalarEvent({required this.isFlowContext});

  @override
  final bool isFlowContext;
}

/// An event that trigger the parsing of a [Node]'s properties
enum NodePropertyEvent implements ParserEvent {
  /// Parse a local tag
  startTag,

  /// Parse a verbatim tag
  startVerbatimTag,

  /// Parse an anchor
  startAnchor,

  /// Parse an alias
  startAlias;

  @override
  bool get isFlowContext => throw UnsupportedError(
    'A node property should not be detected when parsing nodes!',
  );
}

/// An event that triggers parsing of a [Node] with [NodeStyle.block] styling.
enum BlockCollectionEvent implements ParserEvent {
  /// Parse a block list
  startBlockListEntry,

  /// Parse a block map with a key.
  ///
  /// This event is unique and should never be inferred. It requires the
  /// caller to have parsed a(n) (implicit) key belonging to a block map.
  startImplicitKey,

  /// Parse a block map beginning with an explicit key
  startExplicitKey,

  /// Parse a block map value
  startEntryValue;

  @override
  bool get isFlowContext => false;
}

/// An event that triggers parsing of a [Node] with [NodeStyle.flow] styling
enum FlowCollectionEvent implements ParserEvent {
  /// Parse a flow map
  startFlowMap,

  /// Parse an explicit flow map (entry) key
  startExplicitKey,

  /// Parse a flow map (entry) value
  startEntryValue,

  /// End flow map parsing
  endFlowMap,

  /// Parse flow sequence
  startFlowSequence,

  /// End flow sequence parsing
  endFlowSequence,

  /// End of a flow collection entry parsing and beginning of a new one.
  nextFlowEntry;

  @override
  bool get isFlowContext => true;
}

/// Infers a generalized [ParserEvent] that determines how the [DocumentParser]
/// should parse the next collection of characters.
ParserEvent _inferNextEvent(
  GraphemeScanner scanner, {
  required bool isBlockContext,
  required bool lastKeyWasJsonLike,
}) {
  final charAfter = scanner.peekCharAfterCursor();

  /// Can be allowed after map like indicator such as:
  ///   - "?" -> an explicit key indicator
  ///   - ":" -> indicates start of a value
  final canBeSeparation = charAfter.isNullOr(
    (c) => c.isWhiteSpace() || c.isLineBreak(),
  );

  return switch (scanner.charAtCursor) {
    doubleQuote => ScalarEvent.startFlowDoubleQuoted,
    singleQuote => ScalarEvent.startFlowSingleQuoted,
    literal => ScalarEvent.startBlockLiteral,
    folded => ScalarEvent.startBlockFolded,

    mappingValue when isBlockContext && canBeSeparation =>
      BlockCollectionEvent.startEntryValue,

    // Flow node doesn't need the space when key is json-like (double quoted)
    mappingValue
        when !isBlockContext && (canBeSeparation || lastKeyWasJsonLike) =>
      FlowCollectionEvent.startEntryValue,

    blockSequenceEntry when canBeSeparation && isBlockContext =>
      BlockCollectionEvent.startBlockListEntry,

    mappingKey when isBlockContext && canBeSeparation =>
      BlockCollectionEvent.startExplicitKey,

    /// In flow collections, it is allow a "?" to occur separately without any
    /// key beside a "," or "{" or "}" or "[" or "]"
    mappingKey
        when !isBlockContext &&
            (canBeSeparation ||
                charAfter.isNotNullAnd((c) => c.isFlowDelimiter())) =>
      FlowCollectionEvent.startExplicitKey,

    flowSequenceStart => FlowCollectionEvent.startFlowSequence,
    flowSequenceEnd => FlowCollectionEvent.endFlowSequence,
    flowEntryEnd => FlowCollectionEvent.nextFlowEntry,
    mappingStart => FlowCollectionEvent.startFlowMap,
    mappingEnd => FlowCollectionEvent.endFlowMap,

    anchor => NodePropertyEvent.startAnchor,
    alias => NodePropertyEvent.startAlias,
    tag =>
      charAfter == verbatimStart
          ? NodePropertyEvent.startVerbatimTag
          : NodePropertyEvent.startTag,

    _ => ScalarEvent.startFlowPlain,
  };
}
