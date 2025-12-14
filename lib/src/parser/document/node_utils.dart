import 'package:rookie_yaml/src/parser/delegates/parser_delegate.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/node_properties.dart';
import 'package:rookie_yaml/src/parser/document/parser_state.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/parser/scalars/block/block_scalar.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/double_quoted.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/plain.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/single_quoted.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';

/// A parsed flow/block map entry.
typedef ParsedEntry<T> = (ParserDelegate<T> key, ParserDelegate<T>? value);

/// Represents the current state after a block node has been completely parsed.
typedef BlockInfo = ({int? exitIndent, DocumentMarker docMarker});

/// Indicates no nodes can be parsed after the current block node.
const BlockInfo emptyScanner = (
  exitIndent: null,
  docMarker: DocumentMarker.none,
);

/// Represents a generic block-like node and its state.
typedef BlockNodeBuilder<T> = ({BlockInfo blockInfo, T node});

/// A single block node.
typedef BlockNode<T> = BlockNodeBuilder<ParserDelegate<T>>;

/// An explicit/implicit block entry for a map.
typedef BlockEntry<Obj> =
    BlockNodeBuilder<(ParserDelegate<Obj>? key, ParserDelegate<Obj>? value)>;

/// Callback for a block map entry that has been fully parsed.
typedef OnBlockMapEntry<Obj> =
    void Function(ParserDelegate<Obj> key, ParserDelegate<Obj>? value);

/// Parses a [Scalar].
///
/// [greedyOnPlain] is only ever passed when the first two plain scalar
/// characters resemble the directive end markers `---` but the last char
/// is not a match.
(PreScalar scalar, ScalarDelegate<R> delegate) parseScalar<R>(
  ScalarEvent event, {
  required SourceIterator iterator,
  required ScalarFunction<R> scalarFunction,
  required void Function(YamlComment comment) onParseComment,
  required bool isImplicit,
  required bool isInFlowContext,
  required int indentLevel,
  required int minIndent,
  String greedyOnPlain = '',
  RuneOffset? start,
}) {
  final scalarStart = start ?? iterator.currentLineInfo.current;

  final prescalar = switch (event) {
    ScalarEvent.startBlockLiteral || ScalarEvent.startBlockFolded
        when !isImplicit && !isInFlowContext && greedyOnPlain.isEmpty =>
      parseBlockStyle(
        iterator,
        minimumIndent: minIndent,
        indentLevel: indentLevel,
        onParseComment: onParseComment,
      ),

    ScalarEvent.startFlowDoubleQuoted when greedyOnPlain.isEmpty =>
      parseDoubleQuoted(
        iterator,
        indent: minIndent,
        isImplicit: isImplicit,
      ),

    ScalarEvent.startFlowSingleQuoted when greedyOnPlain.isEmpty =>
      parseSingleQuoted(
        iterator,
        indent: minIndent,
        isImplicit: isImplicit,
      ),

    // We are aware of what character is at the start. Cannot be null
    _ when event == ScalarEvent.startFlowPlain || greedyOnPlain.isNotEmpty =>
      parsePlain(
        iterator,
        indent: minIndent,
        charsOnGreedy: greedyOnPlain,
        isImplicit: isImplicit,
        isInFlowContext: isInFlowContext,
      ),

    _ => throwForCurrentLine(
      iterator,
      message: 'Failed to parse block scalar declared in a flow context!',
    ),
  };

  /// This is a failsafe. Every map/list (flow or block) must look for
  /// ways to ensure a `null` plain scalar is never returned. This ensures
  /// the internal parsing logic for parsing the map/list is correct. Each
  /// flow/block map/list handles missing values differently.
  if (prescalar == null) {
    throw throwForCurrentLine(
      iterator,
      message: 'Null was returned when parsing a plain scalar!',
    );
  }

  return (
    prescalar,
    ScalarDelegate(
      indentLevel: indentLevel,
      indent: minIndent,
      start: scalarStart,
      scalarResolver: scalarFunction,
      prescalar: prescalar,
    ),
  );
}

/// Skips to the next parsable flow indicator/character.
///
/// If declared on a new line and [forceInline] is `false`, the flow
/// indicator/character must be indented at least [minIndent] spaces. Throws
/// otherwise.
bool nextSafeLineInFlow(
  SourceIterator iterator, {
  required int minIndent,
  required bool forceInline,
  required void Function(YamlComment comment) onParseComment,
}) {
  final indent = skipToParsableChar(iterator, onParseComment: onParseComment);

  if (indent != null) {
    // Must not have line breaks
    if (forceInline) {
      throwWithApproximateRange(
        iterator,
        message: 'Found a line break when parsing an inline flow node',
        current: iterator.currentLineInfo.current,
        charCountBefore: indent + 2, // Highlight upto the previous line
      );
    }

    /// If line breaks are allowed, it must at least be the same or
    /// greater than the min indent. Indent serves no purpose in flow
    /// collections. The min indent is used as markup indent enforced parent
    /// block collection
    if (indent < minIndent) {
      throwWithApproximateRange(
        iterator,
        message: 'Expected at least ${minIndent - indent} additional spaces',
        current: iterator.currentLineInfo.current,
        charCountBefore: indent,
      );
    }
  } else if (iterator.isEOF) {
    return false;
  }

  return true;
}

/// Returns `true` if [_parseFlowSequence] or [_parseFlowMap] can parse the
/// next flow entry or flow map entry respectively.
bool continueToNextEntry(
  SourceIterator iterator, {
  required int minIndent,
  required bool forceInline,
  required void Function(YamlComment comment) onParseComment,
}) {
  nextSafeLineInFlow(
    iterator,
    minIndent: minIndent,
    forceInline: forceInline,
    onParseComment: onParseComment,
  );

  if (iterator.current != flowEntryEnd) {
    return false;
  }

  iterator.nextChar();
  return nextSafeLineInFlow(
    iterator,
    minIndent: minIndent,
    forceInline: forceInline,
    onParseComment: onParseComment,
  );
}

/// Returns `true` if a flow key was "json-like", that is, a single/double
/// quoted plain scalar or flow map/sequence.
bool keyIsJsonLike(ParserDelegate? delegate) => switch (delegate) {
  ScalarDelegate(
    scalarStyle: ScalarStyle.singleQuoted || ScalarStyle.doubleQuoted,
  ) ||
  MappingDelegate(collectionStyle: NodeStyle.flow) ||
  SequenceDelegate(collectionStyle: NodeStyle.flow) => true,
  _ => false,
};

/// Initializes a flow collection and validates that the [flowStartIndicator]
/// matches the corresponding flow collection's start delimiter. Returns the
/// collection by calling [init].
T initFlowCollection<R, T extends ParserDelegate<R>>(
  SourceIterator iterator, {
  required int flowStartIndicator,
  required int minIndent,
  required bool forceInline,
  required void Function(YamlComment comment) onParseComment,
  required int flowEndIndicator,
  required T Function(RuneOffset start) init,
}) {
  final current = iterator.currentLineInfo.current;

  if (iterator.current != flowStartIndicator) {
    throwWithSingleOffset(
      iterator,
      message:
          'Expected the flow delimiter: '
          '"${flowStartIndicator.asString()}"',
      offset: current,
    );
  }

  iterator.nextChar();

  if (!nextSafeLineInFlow(
    iterator,
    minIndent: minIndent,
    forceInline: forceInline,
    onParseComment: onParseComment,
  )) {
    throwWithRangedOffset(
      iterator,
      message:
          'Invalid flow collection state. Expected to find: '
          '"${flowEndIndicator.asString()}"',
      start: current,
      end: iterator.currentLineInfo.current,
    );
  }

  return init(current);
}

/// Checks if the current char in the [scanner] matches the closing [delimiter]
/// of the flow collection. If valid, the [flowCollection]'s end offset is
/// updated and the [delimiter] is skipped.
D terminateFlowCollection<Obj, D extends ParserDelegate<Obj>>(
  SourceIterator iterator,
  D flowCollection,
  int delimiter,
) {
  final offset = iterator.currentLineInfo.current;

  if (iterator.current != delimiter) {
    throwWithSingleOffset(
      iterator,
      message:
          'Invalid flow collection state. Expected '
          '"${delimiter.asString()}"',
      offset: offset,
    );
  }

  flowCollection.updateEndOffset = offset;
  iterator.nextChar();
  return flowCollection;
}

/// Creates a `null` delegate.
ParserDelegate<Obj>
nullBlockNode<Obj, Seq extends Iterable<Obj>, Dict extends Map<Obj, Obj?>>(
  ParserState<Obj, Seq, Dict> state, {
  required int indentLevel,
  required int indent,
  required RuneOffset start,
}) => emptyBlockNode(
  state,
  property: ParsedProperty.empty(
    start,
    start,
    null,
    spanMultipleLines: false,
  ),
  indentLevel: indentLevel,
  indent: indent,
  end: start,
);

/// Creates a `null` delegate only if [property] is not an [Alias].
ParserDelegate<Obj>
emptyBlockNode<Obj, Seq extends Iterable<Obj>, Dict extends Map<Obj, Obj?>>(
  ParserState<Obj, Seq, Dict> state, {
  required ParsedProperty property,
  required int indentLevel,
  required int indent,
  required RuneOffset end,
}) {
  final offset = property.span.start;

  final node = switch (property) {
    Alias _ => state.referenceAlias(
      property,
      indentLevel: indentLevel,
      indent: indent,
      start: offset,
    ),
    _ => nullScalarDelegate(
      indentLevel: indentLevel,
      indent: indent,
      startOffset: offset,
      resolver: state.scalarFunction,
    ),
  };

  return state.trackAnchor(node..updateEndOffset = end, property)
    ..hasLineBreak = property.isMultiline;
}

/// Calculates the indent for a block node within a block collection
/// only if [inferred] indent is null.
({int laxIndent, int inlineFixedIndent}) indentOfBlockChild(
  int? inferred, {
  required int blockParentIndent,
  required int yamlNodeStartOffset,
  required int contentOffset,
}) {
  if (inferred != null) {
    return (laxIndent: inferred, inlineFixedIndent: inferred);
  }

  /// Being null indicates the child is okay being indented at least "+1" if
  /// the rest of its content spans multiple lines. This applies to
  /// [ScalarStyle.literal] and [ScalarStyle.folded]. Flow collections also
  /// benefit from this as the indent serves no purpose other than respecting
  /// the current block parent's indentation. This is its [laxIndent].
  ///
  /// Its [inlineFixedIndent] is the character difference upto the current
  /// parsable char. This indent is enforced on block sequences and maps used
  /// as:
  ///   1. a block sequence entry
  ///   2. content of an explicit key
  ///   3. content of an explicit key's value
  ///
  /// "?" is used as an example but applies to all block nodes that use an
  /// indicator.
  ///
  /// (meh! No markdown hover)
  /// ```yaml
  ///
  /// # With flow. Okay
  /// ? [
  ///  "blah", "blah",
  ///  "blah"]
  ///
  /// # With literal. Applies to folded. Okay
  /// ? |
  ///  block
  ///
  /// # With literal. Applies to folded. We give "+1". Indent determined
  /// # while parsing as recommended by YAML. See [parseBlockStyle]
  /// ? |
  ///     block
  ///
  /// # With block sequences. Must do this for okay
  /// ? - blah
  ///   - blah
  ///
  /// # With implicit or explict map
  /// ? key: value
  ///   keyB: value
  ///   keyC: value # Explicit key ends here
  /// : actual-value # Explicit key's value
  ///
  /// # With block sequence. If this is done. Still okay. Inferred.
  /// ?
  ///  - blah
  ///  - blah
  ///
  /// ```
  return (
    laxIndent: blockParentIndent + 1,
    inlineFixedIndent:
        blockParentIndent + (contentOffset - yamlNodeStartOffset),
  );
}
