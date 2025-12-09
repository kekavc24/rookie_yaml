import 'package:rookie_yaml/src/parser/delegates/parser_delegate.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_sequence.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_wildcard.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/implicit_block_entry.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/node_properties.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/parser_state.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Information after a special block sequence has been parsed.
///
/// See [composeSpecialBlockSequence] and [parseSpecialBlockSequence].
typedef SpecialBlockSequenceInfo = ({
  bool parsedNextImplicitKey,
  BlockInfo blockInfo,
});

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
SpecialBlockSequenceInfo composeSpecialBlockSequence<
  Obj,
  Seq extends Iterable<Obj>,
  Dict extends Map<Obj, Obj?>
>(
  ParserState<Obj, Seq, Dict> state, {
  required BlockNode<Obj> blockNode,
  required int keyIndent,
  required int keyIndentLevel,
  required void Function(ParserDelegate<Obj> sequence) onSequenceOrBlockNode,
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
SpecialBlockSequenceInfo parseSpecialBlockSequence<
  Obj,
  Seq extends Iterable<Obj>,
  Dict extends Map<Obj, Obj?>
>(
  ParserState<Obj, Seq, Dict> state, {
  required int keyIndent,
  required int keyIndentLevel,
  required ParsedProperty? property,
  required void Function(ParserDelegate<Obj> sequence) onSequence,
  required OnBlockMapEntry<Obj> onNextImplicitEntry,
}) {
  final ParserState(:iterator) = state;

  final (:greedyOnPlain, :sequence) = parseBlockSequence(
    SequenceDelegate.byKind(
      kind: property?.kind ?? NodeKind.sequence,
      style: NodeStyle.block,
      indent: keyIndent,
      indentLevel: keyIndentLevel,
      start: property?.span.start ?? iterator.currentLineInfo.current,
      resolver: state.listFunction,
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
