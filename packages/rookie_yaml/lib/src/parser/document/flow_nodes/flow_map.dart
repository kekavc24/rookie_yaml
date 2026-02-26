import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/flow_nodes/flow_map_entry.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/state/parser_state.dart';
import 'package:rookie_yaml/src/scanner/encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/span.dart';
import 'package:rookie_yaml/src/schema/yaml_node.dart';

/// Parses a flow map.
///
/// If [forceInline] is `true`, the map must be declared on the same line
/// with no line breaks and throws if otherwise.
NodeDelegate<Obj> parseFlowMap<Obj>(
  ParserState<Obj> state, {
  required int indentLevel,
  required int minIndent,
  required bool forceInline,
  ObjectFromMap<Obj, Obj, Obj>? asCustomMap,
}) {
  final ParserState(:iterator, :comments, :onMapDuplicate) = state;

  bool goToNext(YamlSourceSpan entrySpan) => continueToNextEntry(
    iterator,
    lastEntrySpan: entrySpan,
    minIndent: minIndent,
    forceInline: forceInline,
    onParseComment: comments.add,
  );

  final map = initFlowCollection(
    iterator,
    flowStartIndicator: mappingStart,
    minIndent: minIndent,
    forceInline: forceInline,
    onParseComment: comments.add,
    flowEndIndicator: mappingEnd,
    init: (start) {
      if (asCustomMap != null) {
        return MapLikeDelegate.boxed(
          asCustomMap.onCustomMap(),
          collectionStyle: NodeStyle.flow,
          indentLevel: indentLevel,
          indent: minIndent,
          start: start,
          afterMapping: asCustomMap.afterObject<Obj>(),
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
        key.nodeSpan.nodeStart,
        value?.nodeSpan.nodeStart ?? iterator.currentLineInfo.current,
        'A flow map cannot contain duplicate entries by the same key',
      );
    }

    if (!goToNext(value?.nodeSpan ?? key.nodeSpan)) break;
  } while (!iterator.isEOF);

  return terminateFlowCollection(iterator, map, mappingEnd);
}
