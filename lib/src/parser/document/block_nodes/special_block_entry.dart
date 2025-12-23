import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_sequence.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_wildcard.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/implicit_block_entry.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/node_properties.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/nodes_by_kind/node_kind.dart';
import 'package:rookie_yaml/src/parser/document/state/parser_state.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Information after a special block sequence has been parsed.
///
/// See [composeSpecialBlockSequence] and [parseSpecialBlockSequence].
typedef SpecialBlockSequenceInfo = ({
  bool parsedNextImplicitKey,
  BlockInfo blockInfo,
});

/// Creates a [SequenceLikeDelegate] based on its kind.
///
/// An [IterableToObjectDelegate] may be returned if the parser was instructed
/// to treat a specific tag embedded in the node's [property] as a [CustomKind].
/// Otherwise, a generic [SequenceDelegate] is returned.
SequenceLikeDelegate<Obj, Obj> _delegateHelper<Obj>(
  ParsedProperty? property, {
  required RuneOffset start,
  required int indent,
  required int indentLevel,
  required ParserState<Obj> state,
}) {
  // Check if this special sequence was annotated with custom properties
  if (property case NodeProperty(
    kind: CustomKind.iterable,
    customResolver: ObjectFromIterable<Obj>(:final onCustomIterable),
  )) {
    return SequenceLikeDelegate.boxed(
      onCustomIterable(),
      collectionStyle: NodeStyle.block,
      indentLevel: indentLevel,
      indent: indent,
      start: start,
    );
  }

  return state.defaultSequenceDelegate(
    style: NodeStyle.block,
    indent: indent,
    indentLevel: indentLevel,
    start: start,
    kind: property?.kind ?? YamlKind.sequence,
  );
}

/// Attempts to parse a block sequence on the same indent level as its implicit
/// key or explicit key/value.
///
/// ```yaml
/// ?
/// - explicit key
/// :
/// - explicit value
/// ```
///
/// OR
///
/// ```yaml
/// implicit key:
/// - value
/// ```
///
/// If the sequence is parsed, [onSequenceOrBlockNode] will be called.
/// [onNextImplicitEntry] will be called after the next implicit entry has been
/// parsed. In this case, the block sequence must have exited after encountering
/// "directive end"-ish characters.
///
/// ```yaml
/// key:
/// - sequence
///
/// # These are implicit keys
/// -- key: value
/// ---another: key
/// ```
SpecialBlockSequenceInfo composeSpecialBlockSequence<Obj>(
  ParserState<Obj> state, {
  required BlockNode<Obj> blockNode,
  required int keyIndent,
  required int keyIndentLevel,
  required void Function(NodeDelegate<Obj> sequence) onSequenceOrBlockNode,
  required OnBlockMapEntry<Obj> onNextImplicitEntry,
}) {
  final (:blockInfo, :node) = blockNode;

  if (node case ScalarDelegate(isNullDelegate: true)
      when !state.iterator.isEOF &&
          !blockInfo.docMarker.stopIfParsingDoc &&
          blockInfo.exitIndent == keyIndent &&
          inferBlockEvent(state.iterator) ==
              BlockCollectionEvent.startBlockListEntry) {
    return parseSpecialBlockSequence(
      state,
      keyIndent: keyIndent,
      keyIndentLevel: keyIndentLevel,
      property: node.property,
      onSequence: onSequenceOrBlockNode,
      onNextImplicitEntry: onNextImplicitEntry,
    );
  }

  onSequenceOrBlockNode(node);
  return (parsedNextImplicitKey: false, blockInfo: blockInfo);
}

/// Parses a block sequence on the same indent level as its implicit key or
/// explicit key/value.
///
/// ```yaml
/// ?
/// - explicit key
/// :
/// - explicit value
/// ```
///
/// OR
///
/// ```yaml
/// implicit key:
/// - value
/// ```
///
/// If the sequence is parsed, [onSequence] will be called.
/// [onNextImplicitEntry] will be called after the next implicit entry has been
/// parsed. In this case, the block sequence must have exited after encountering
/// "directive end"-ish characters.
///
/// ```yaml
/// key:
/// - sequence
///
/// # These are implicit keys
/// -- key: value
/// ---another: key
/// ```
SpecialBlockSequenceInfo parseSpecialBlockSequence<Obj>(
  ParserState<Obj> state, {
  required int keyIndent,
  required int keyIndentLevel,
  required ParsedProperty? property,
  required void Function(NodeDelegate<Obj> sequence) onSequence,
  required OnBlockMapEntry<Obj> onNextImplicitEntry,
}) {
  final ParserState(:iterator) = state;

  final (:greedyOnPlain, :sequence) = parseBlockSequence(
    _delegateHelper<Obj>(
      property,
      state: state,
      start: property?.span.start ?? iterator.currentLineInfo.current,
      indent: keyIndent,
      indentLevel: keyIndentLevel,
    )..updateNodeProperties = property,
    state: state,
    levelWithBlockMap: true,
  );

  onSequence(sequence.node);

  // We are not eating into the next implicit plain key with "--"
  if (greedyOnPlain == null || greedyOnPlain.isEmpty) {
    return (parsedNextImplicitKey: false, blockInfo: sequence.blockInfo);
  }

  // Recover the next key we consumed.
  final (blockInfo: keyInfo, node: implicitKey) = parseBlockScalar(
    state,
    event: ScalarEvent.startFlowPlain,
    blockParentIndent: null,
    minIndent: keyIndent,
    indentLevel: keyIndentLevel,
    isImplicit: true,
    scalarProperty: null,
    composeImplicitMap: false,
    composedMapIndent: -1,
    greedyOnPlain: greedyOnPlain,
  );

  return (
    parsedNextImplicitKey: true,
    blockInfo: parseImplicitValue(
      state,
      keyIndentLevel: keyIndentLevel,
      keyIndent: keyIndent,
      onValue: (implicitValue) => onNextImplicitEntry(
        implicitKey,
        implicitValue,
      ),
      onEntryValue: onNextImplicitEntry,
    ),
  );
}
