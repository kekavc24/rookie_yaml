import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/flow_nodes/flow_map_entry.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/state/parser_state.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Parses a flow map.
///
/// If [forceInline] is `true`, the map must be declared on the same line
/// with no line breaks and throws if otherwise.
NodeDelegate<Obj> parseFlowMap<Obj>(
  ParserState<Obj> state, {
  required int indentLevel,
  required int minIndent,
  required bool forceInline,
  OnCustomMap<Obj>? asCustomMap,
}) {
  final ParserState(:iterator, :comments, :onMapDuplicate) = state;

  final map = initFlowCollection(
    iterator,
    flowStartIndicator: mappingStart,
    minIndent: minIndent,
    forceInline: forceInline,
    onParseComment: comments.add,
    flowEndIndicator: mappingEnd,
    init: (start) {
      if (asCustomMap != null) {
        return MapLikeDelegate<Obj, Obj>.boxed(
          asCustomMap(),
          collectionStyle: NodeStyle.flow,
          indentLevel: indentLevel,
          indent: minIndent,
          start: start,
        );
      }

      return state.defaultMapDelegate(
        mapStyle: NodeStyle.flow,
        indentLevel: indentLevel,
        indent: minIndent,
        start: start,
      );
    },
  );

  do {
    if (iterator.current case flowEntryEnd || mappingEnd) {
      break;
    }

    final (key, value) = switch (inferNextEvent(
      iterator,
      isBlockContext: false,
      lastKeyWasJsonLike: false,
    )) {
      FlowCollectionEvent.startExplicitKey => parseExplicitEntry(
        state,
        indentLevel: indentLevel,
        minIndent: minIndent,
        forceInline: forceInline,
      ),
      _ => parseImplicitEntry(
        state,
        indentLevel: indentLevel,
        minIndent: minIndent,
        forceInline: forceInline,
      ),
    };

    if (!map.accept(key.parsed(), value?.parsed())) {
      onMapDuplicate(
        key.start,
        value?.start ?? iterator.currentLineInfo.current,
        'A flow map cannot contain duplicate entries by the same key',
      );
    }

    map.hasLineBreak =
        key.encounteredLineBreak || (value?.encounteredLineBreak ?? false);

    if (!continueToNextEntry(
      iterator,
      minIndent: minIndent,
      forceInline: forceInline,
      onParseComment: comments.add,
    )) {
      break;
    }
  } while (!iterator.isEOF);

  return terminateFlowCollection(iterator, map, mappingEnd);
}
