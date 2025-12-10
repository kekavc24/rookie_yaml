import 'package:rookie_yaml/src/parser/delegates/parser_delegate.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_map.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_node.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/flow_nodes/flow_map.dart';
import 'package:rookie_yaml/src/parser/document/flow_nodes/flow_sequence.dart';
import 'package:rookie_yaml/src/parser/document/node_properties.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/parser_state.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Composes a block node using the current [event] and throws if it is not a
/// block map.
BlockNode<Obj> composeBlockMapStrict<
  Obj,
  Seq extends Iterable<Obj>,
  Dict extends Map<Obj, Obj?>
>(
  ParserState<Obj, Seq, Dict> state, {
  required int indentLevel,
  required int laxIndent,
  required int inlineFixedIndent,
  required NodeProperty property,
  required bool isInline,
  required bool composeImplicitMap,
}) {
  /// Parse as a wildcard but expect it to degenerate to a block map
  /// since we cannot determine this at the current stack level.
  final mapInfo = parseBlockNode(
    state,
    indentLevel: indentLevel,

    // Won't matter. The lax and inline indent are predetermined already.
    inferredFromParent: null,
    laxBlockIndent: laxIndent,
    fixedInlineIndent: inlineFixedIndent,
    forceInlined: isInline,
    composeImplicitMap: composeImplicitMap,
  );

  final node = mapInfo.node;

  if (node is! MappingDelegate) {
    throwWithRangedOffset(
      state.iterator,
      message:
          'Expected an (implied) block map with property '
          '"${property.tag ?? property.anchor}"',

      start: property.span.start,
      end: mapInfo.node.endOffset!,
    );
  }

  state.trackAnchor(node, property);
  return mapInfo;
}

/// Parses a valid block node matching the [event].
BlockNode<Obj>
parseBlockWildCard<Obj, Seq extends Iterable<Obj>, Dict extends Map<Obj, Obj?>>(
  ParserState<Obj, Seq, Dict> state, {
  required ParserEvent event,
  required int indentLevel,
  required int laxIndent,
  required int inlineFixedIndent,
  required ParsedProperty property,
  required bool isInline,
  required bool composeImplicitMap,
}) => switch (event) {
  BlockCollectionEvent.startEntryValue => composeBlockMapFromScalar(
    state,
    keyOrNode: nullScalarDelegate(
      indentLevel: indentLevel,
      indent: laxIndent,
      startOffset: state.iterator.currentLineInfo.current,
      resolver: state.scalarFunction,
    )..updateEndOffset = state.iterator.currentLineInfo.current,
    keyOrMapProperty: property,
    indentOnExit: property.indentOnExit,
    documentMarker: DocumentMarker.none,
    keyIsBlock: false,
    composeImplicitMap: composeImplicitMap,
    composedMapIndent: inlineFixedIndent,
  ),
  BlockCollectionEvent.startExplicitKey => parseBlockMap(
    MappingDelegate(
      collectionStyle: NodeStyle.block,
      indentLevel: indentLevel,
      indent: inlineFixedIndent,
      start: state.iterator.currentLineInfo.current,
      mapResolver: state.mapFunction,
    ),
    state: state,
  ),
  FlowCollectionEvent event => parseFlowNodeInBlock(
    state,
    event: event,
    indentLevel: indentLevel,
    indent: laxIndent,
    isInline: isInline,
    composeImplicitMap: composeImplicitMap,
    flowProperty: property,
    composedMapIndent: inlineFixedIndent,
  ),
  ScalarEvent() => parseBlockScalar(
    state,
    event: event,
    minIndent: laxIndent,
    indentLevel: indentLevel,
    isImplicit: isInline,
    scalarProperty: property,
    composeImplicitMap: composeImplicitMap,
    composedMapIndent: inlineFixedIndent,
  ),
  _ => throwWithRangedOffset(
    state.iterator,
    message: 'Block node found in a unparsable state',
    start: property.span.start,
    end: state.iterator.currentLineInfo.current,
  ),
};

/// Parses a flow collection that is a top level block node or embedded in a
/// block node.
///
/// If [composeImplicitMap] is `true` and the flow collection was inline then
/// a block map may be composed.
BlockNode<Obj> parseFlowNodeInBlock<
  Obj,
  Seq extends Iterable<Obj>,
  Dict extends Map<Obj, Obj?>
>(
  ParserState<Obj, Seq, Dict> state, {
  required FlowCollectionEvent event,
  required int indentLevel,
  required int indent,
  required bool isInline,
  required bool composeImplicitMap,
  required int composedMapIndent,
  required ParsedProperty flowProperty,
}) {
  // All flow events must be start of flow map or sequence
  final flow = switch (event) {
    FlowCollectionEvent.startFlowMap => parseFlowMap(
      state,
      indentLevel: indentLevel,
      minIndent: indent,
      forceInline: isInline,
    ),
    FlowCollectionEvent.startFlowSequence => parseFlowSequence(
      state,
      indentLevel: indentLevel,
      minIndent: indent,
      forceInline: isInline,
    ),
    _ => throwWithRangedOffset(
      state.iterator,
      message: 'Invalid flow node state. Expected "{" or "]"',
      start: flowProperty.span.start,
      end: state.iterator.currentLineInfo.current,
    ),
  };

  final indentOfNextNode = skipToParsableChar(
    state.iterator,
    comments: state.comments,
  );

  // Some flow collections can be used as keys like scalars.
  return composeBlockMapFromScalar(
    state,
    keyOrNode: flow,
    keyOrMapProperty: flowProperty,
    indentOnExit: indentOfNextNode,
    documentMarker: DocumentMarker.none,
    keyIsBlock: false,
    composeImplicitMap: composeImplicitMap && indentOfNextNode == null,
    composedMapIndent: composedMapIndent,
  );
}

/// Parses a block scalar based on the current scalar [event] and optionally
/// composes a block if [composeImplicitMap] is `true` and the [Scalar] is a
/// flow scalar.
BlockNode<Obj>
parseBlockScalar<Obj, Seq extends Iterable<Obj>, Dict extends Map<Obj, Obj?>>(
  ParserState<Obj, Seq, Dict> state, {
  required ScalarEvent event,
  required int minIndent,
  required int indentLevel,
  required bool isImplicit,
  required ParsedProperty? scalarProperty,
  required bool composeImplicitMap,
  required int composedMapIndent,
  String greedyOnPlain = '',
  RuneOffset? start,
}) {
  final ParserState(:iterator, :comments, :scalarFunction) = state;

  final (
    PreScalar(
      :docMarkerType,
      :indentDidChange,
      :indentOnExit,
      :hasLineBreak,
    ),
    delegate,
  ) = parseScalar(
    event,
    iterator: iterator,
    scalarFunction: scalarFunction,
    onParseComment: comments.add,
    isImplicit: isImplicit,
    isInFlowContext: false,
    indentLevel: indentLevel,
    minIndent: minIndent,
    greedyOnPlain: greedyOnPlain,
    start: start,
  );

  return composeBlockMapFromScalar(
    state,
    keyOrNode: delegate,
    keyOrMapProperty: scalarProperty,
    indentOnExit: indentOnExit,
    documentMarker: docMarkerType,

    // Plain scalar behaved like a block scalar if indent changed.
    keyIsBlock: !event.isFlowContext || indentDidChange,
    composeImplicitMap: composeImplicitMap,
    composedMapIndent: composedMapIndent,
  );
}
