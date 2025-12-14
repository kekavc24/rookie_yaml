part of 'custom_node.dart';

/// Parses a custom block node based on the [kind].
BlockNode<Obj> customBlockNode<Obj>(
  CustomKind kind, {
  required ParserState<Obj> state,
  required ParserEvent event,
  required NodeProperty property,
  required int indentLevel,
  required int laxBlockIndent,
  required int fixedInlineIndent,
  required bool forceInlined,
  required bool composeImplicitMap,
}) {
  BlockNode<Obj> flowOrBlock({
    required BlockNode<Obj> Function() ifBlock,
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
        {
          customNode = ifBlock();
          state.trackAnchor(customNode.node, property);
        }
    }

    if (composeImplicitMap && customNode.node is! MapLikeDelegate) {
      throwWithRangedOffset(
        state.iterator,
        message: 'Expected an custom map',
        start: property.span.start,
        end: customNode.node.endOffset!,
      );
    }

    return customNode;
  }

  return _parseCustomKind<BlockNode<Obj>, Obj>(
    kind,
    property: property,
    onMatchMap: (mapBuilder) => flowOrBlock(
      ifBlock: () => parseBlockMap(
        mapBuilder(
              NodeStyle.block,
              indentLevel,
              fixedInlineIndent,
              property.span.start,
            )
            as MapLikeDelegate<Obj, Obj>,
        state: state,
      ),
      ifFlowMap: mapBuilder,
    ),
    onMatchIterable: (listBuilder) => flowOrBlock(
      ifBlock: () => parseBlockSequence(
        listBuilder(
              NodeStyle.block,
              indentLevel,
              fixedInlineIndent,
              property.span.start,
            )
            as SequenceLikeDelegate<Obj, Obj>,
        state: state,
        levelWithBlockMap: false,
      ).sequence,
      ifFlowList: listBuilder,
    ),
    onMatchScalar: (resolver) {
      // We want the custom object to bubble up as whatever is needed and not
      // the null.
      final actualEvent = event == BlockCollectionEvent.startEntryValue
          ? ScalarEvent.startFlowPlain
          : event;

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
          indentLevel: indentLevel,
          minIndent: laxBlockIndent,
        );

        return flowOrBlock(
          ifBlock: () => composeBlockMapFromScalar(
            state,
            keyOrNode: node,
            keyOrMapProperty: property,
            indentOnExit: exitIndent,
            documentMarker: docMarker,
            keyIsBlock:
                composeImplicitMap && exitIndent != seamlessIndentMarker,
            composeImplicitMap: composeImplicitMap,
            composedMapIndent: fixedInlineIndent,
          ),
        );
      }

      throwWithRangedOffset(
        state.iterator,
        message: 'Expected a scalar that can be parsed as a custom node',
        start: property.span.start,
        end: state.iterator.currentLineInfo.current,
      );
    },
  );
}
