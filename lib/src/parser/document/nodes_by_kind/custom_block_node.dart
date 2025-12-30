part of 'custom_node.dart';

/// Parses a custom block node based on the [kind].
BlockNode<Obj> customBlockNode<Obj>(
  CustomKind kind, {
  required ParserState<Obj> state,
  required ParserEvent event,
  required NodeProperty property,
  required int? blockParentIndent,
  required int indentLevel,
  required int laxBlockIndent,
  required int fixedInlineIndent,
  required bool forceInlined,
  required bool composeImplicitMap,
  required bool expectBlockMap,
}) {
  BlockNode<Obj> mapEnforcer(BlockNode<Obj> object, {bool enforceMap = false}) {
    if ((enforceMap || expectBlockMap) && object.node is! MapLikeDelegate) {
      throwWithRangedOffset(
        state.iterator,
        message: 'Expected a custom map',
        start: property.span.start,
        end: object.node.endOffset!,
      );
    }

    return object;
  }

  // Handler for a flow or block node.
  BlockNode<Obj> flowOrBlockCollection({
    required BlockNode<Obj> Function() ifBlock,
    bool enforceMap = false,
    OnCustomList<Obj>? ifFlowList,
    OnCustomMap<Obj>? ifFlowMap,
  }) {
    BlockNode<Obj> customNode;

    switch (event) {
      case FlowCollectionEvent():
        {
          // Flow node will be given the property.
          customNode = parseFlowNodeInBlock(
            state,
            event: event,
            indentLevel: indentLevel,
            indent: laxBlockIndent,
            isInline: forceInlined,
            composeImplicitMap: composeImplicitMap,
            composedMapIndent: fixedInlineIndent,
            flowProperty: property,
            asCustomList: ifFlowList,
            asCustomMap: ifFlowMap,
          );
        }

      case BlockCollectionEvent.startBlockListEntry ||
          BlockCollectionEvent.startExplicitKey:
        {
          throwIfInlineInBlock(
            state.iterator,
            isInline: forceInlined,
            property: property,
            currentOffset: state.iterator.currentLineInfo.current,
            identifier: 'A block sequence/map',
          );
          continue block;
        }

      block:
      default:
        customNode = ifBlock();
        state.trackAnchor(customNode.node, property);
    }

    return mapEnforcer(customNode, enforceMap: enforceMap);
  }

  return _parseCustomKind<BlockNode<Obj>, Obj>(
    kind,
    property: property,
    onMatchMap: (mapBuilder) => flowOrBlockCollection(
      enforceMap: true,
      ifBlock: () => parseBlockMap(
        MapLikeDelegate.boxed(
          mapBuilder(),
          collectionStyle: NodeStyle.block,
          indentLevel: indentLevel,
          indent: fixedInlineIndent,
          start: property.span.start,
        ),
        state: state,
      ),
      ifFlowMap: mapBuilder,
    ),
    onMatchIterable: (listBuilder) => flowOrBlockCollection(
      ifBlock: () => parseBlockSequence(
        SequenceLikeDelegate<Obj, Obj>.boxed(
          listBuilder(),
          collectionStyle: NodeStyle.block,
          indentLevel: indentLevel,
          indent: fixedInlineIndent,
          start: property.span.start,
        ),
        state: state,
        levelWithBlockMap: false,
      ).sequence,
      ifFlowList: listBuilder,
    ),
    onMatchScalar: (resolver) => mapEnforcer(
      customBlockScalar(
        event,
        state: state,
        resolver: resolver,
        property: property,
        blockParentIndent: blockParentIndent,
        indentLevel: indentLevel,
        laxBlockIndent: laxBlockIndent,
        fixedInlineIndent: fixedInlineIndent,
        forceInlined: forceInlined,
        composeImplicitMap: composeImplicitMap,
      ),
    ),
  );
}

/// Parses a custom block scalar.
BlockNode<Obj> customBlockScalar<Obj>(
  ParserEvent scalarEvent, {
  required ParserState<Obj> state,
  required OnCustomScalar<Obj> resolver,
  required NodeProperty property,
  required int? blockParentIndent,
  required int indentLevel,
  required int laxBlockIndent,
  required int fixedInlineIndent,
  required bool forceInlined,
  required bool composeImplicitMap,
}) {
  // We want the custom object to bubble up as whatever is needed and not
  // the null.
  final actualEvent = scalarEvent == BlockCollectionEvent.startEntryValue
      ? ScalarEvent.startFlowPlain
      : scalarEvent;

  if (actualEvent is ScalarEvent) {
    final (exitIndent, docMarker, node) = parseCustomScalar(
      actualEvent,
      iterator: state.iterator,
      resolver: resolver,
      property: property,
      onParseComment: state.comments.add,
      onScalar: (_, indentOnExit, _, marker, delegate) =>
          (indentOnExit, marker, delegate),
      isImplicit: forceInlined,
      isInFlowContext: false,
      blockParentIndent: blockParentIndent,
      indentLevel: indentLevel,
      minIndent: laxBlockIndent,
    );

    return composeBlockMapFromScalar(
      state,
      keyOrNode: node,
      keyOrMapProperty: property,
      indentOnExit: exitIndent,
      documentMarker: docMarker,
      keyIsBlock: composeImplicitMap && exitIndent != seamlessIndentMarker,
      composeImplicitMap: composeImplicitMap,
      composedMapIndent: fixedInlineIndent,
    );
  }

  throwWithRangedOffset(
    state.iterator,
    message: 'Expected a scalar that can be parsed as a custom node',
    start: property.span.start,
    end: state.iterator.currentLineInfo.current,
  );
}
