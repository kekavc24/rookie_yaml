part of 'custom_node.dart';

/// Parses a custom flow node based on its [kind].
NodeDelegate<Obj> customFlowNode<Obj>(
  CustomKind kind, {
  required ParserState<Obj> state,
  required NodeProperty property,
  required ParserEvent flowEvent,
  required int currentIndentLevel,
  required int minIndent,
  required bool isImplicit,
  required bool forceInline,
}) => _parseCustomKind<NodeDelegate<Obj>, Obj>(
  kind,
  property: property,
  onMatchMap: (builder) => parseFlowMap(
    state,
    indentLevel: currentIndentLevel,
    minIndent: minIndent,
    forceInline: forceInline,
    asCustomMap: builder,
  ),
  onMatchIterable: (builder) => parseFlowSequence(
    state,
    indentLevel: currentIndentLevel,
    minIndent: minIndent,
    forceInline: forceInline,
    asCustomList: builder,
  ),
  onMatchScalar: (resolver) {
    // Recover this custom null scalar on their behalf.
    final forcedEvent = flowEvent is ScalarEvent
        ? flowEvent
        : ScalarEvent.startFlowPlain;

    return parseCustomScalar(
      forcedEvent,
      iterator: state.iterator,
      resolver: resolver,
      property: property,
      onParseComment: (_) {}, // Flow nodes cannot have comments
      onScalar: (style, indentOnExit, indentDidChange, marker, delegate) {
        if (forceInline || style != ScalarStyle.plain) {
          return delegate;
        }

        // Flow node only ends after parsing a flow delimiter
        if (marker.stopIfParsingDoc) {
          throwForCurrentLine(
            state.iterator,
            message:
                'Premature document termination after parsing a custom plain '
                'scalar',
          );
        } else if (indentDidChange && indentOnExit < minIndent) {
          throwWithApproximateRange(
            state.iterator,
            message:
                'Indent change detected after a custom scalar. Expected'
                ' $minIndent space(s) but found $indentOnExit space(s)',
            current: state.iterator.currentLineInfo.current,
            charCountBefore: indentOnExit,
          );
        }

        return delegate;
      },
      isImplicit: isImplicit,
      isInFlowContext: true,
      indentLevel: currentIndentLevel,
      minIndent: minIndent,
      blockParentIndent: null,
    );
  },
);
