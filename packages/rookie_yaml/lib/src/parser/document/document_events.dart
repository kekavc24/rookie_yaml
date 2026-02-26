import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';

/// A event that controls the `DocumentParser`'s next parse action
abstract interface class ParserEvent {
  /// Returns `true` if the `DocumentParser` is parsing a [YamlSourceNode] with
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

/// An event that trigger the parsing of a [YamlSourceNode]'s properties
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

/// An event that triggers parsing of a [YamlSourceNode] with [NodeStyle.block]
/// styling.
enum BlockCollectionEvent implements ParserEvent {
  /// Parse a block list
  startBlockListEntry,

  /// Parse a block map beginning with an explicit key
  startExplicitKey,

  /// Parse a block map value
  startEntryValue;

  @override
  bool get isFlowContext => false;
}

/// An event that triggers parsing of a [YamlSourceNode] with [NodeStyle.flow]
/// styling
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
ParserEvent inferNextEvent(
  SourceIterator iterator, {
  required bool isBlockContext,
  required bool lastKeyWasJsonLike,
}) {
  final charAfter = iterator.peekNextChar();

  // Can be allowed after map like indicator such as:
  //   - "?" -> an explicit key indicator
  //   - ":" -> indicates start of a value
  final canBeSeparation = charAfter.isNullOr(
    (c) => c.isWhiteSpace() || c.isLineBreak(),
  );

  return switch (iterator.current) {
    doubleQuote => ScalarEvent.startFlowDoubleQuoted,
    singleQuote => ScalarEvent.startFlowSingleQuoted,
    literal => ScalarEvent.startBlockLiteral,
    folded => ScalarEvent.startBlockFolded,

    mappingValue when isBlockContext && canBeSeparation =>
      BlockCollectionEvent.startEntryValue,

    // Flow node doesn't need the space when key is json-like (double quoted)
    mappingValue
        when !isBlockContext &&
            (canBeSeparation ||
                lastKeyWasJsonLike ||
                charAfter.isNotNullAnd((c) => c.isFlowDelimiter())) =>
      FlowCollectionEvent.startEntryValue,

    blockSequenceEntry when canBeSeparation =>
      BlockCollectionEvent.startBlockListEntry,

    mappingKey when isBlockContext && canBeSeparation =>
      BlockCollectionEvent.startExplicitKey,

    // In flow collections, it is allow a "?" to occur separately without any
    // key beside a "," or "{" or "}" or "[" or "]"
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

/// Infers the next block event.
ParserEvent inferBlockEvent(SourceIterator iterator) => inferNextEvent(
  iterator,
  isBlockContext: true,
  lastKeyWasJsonLike: false,
);
