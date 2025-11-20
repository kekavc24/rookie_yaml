import 'package:rookie_yaml/src/parser/delegates/parser_delegate.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/flow_nodes/flow_map_entry.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/parser_state.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Parses a flow map.
///
/// If [forceInline] is `true`, the map must be declared on the same line
/// with no line breaks and throws if otherwise.
MappingDelegate<Obj, Dict>
parseFlowMap<Obj, Seq extends Iterable<Obj>, Dict extends Map<Obj, Obj?>>(
  ParserState<Obj, Seq, Dict> state, {
  required int indentLevel,
  required int minIndent,
  required bool forceInline,
}) {
  final ParserState(:scanner, :comments, :mapFunction, :onMapDuplicate) = state;

  final map = initFlowCollection(
    scanner,
    flowStartIndicator: mappingStart,
    minIndent: minIndent,
    forceInline: forceInline,
    onParseComment: comments.add,
    flowEndIndicator: mappingEnd,
    init: (start) => MappingDelegate<Obj, Dict>(
      collectionStyle: NodeStyle.flow,
      indentLevel: indentLevel,
      indent: minIndent,
      start: start,
      mapResolver: mapFunction,
    ),
  );

  do {
    if (scanner.charAtCursor case null || flowEntryEnd || mappingEnd) {
      break;
    }

    final (key, value) = switch (inferNextEvent(
      scanner,
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
        value?.start ?? scanner.lineInfo().current,
        'A flow map cannot contain duplicate entries by the same key',
      );
    }

    map.hasLineBreak =
        key.encounteredLineBreak || (value?.encounteredLineBreak ?? false);

    if (!continueToNextEntry(
      scanner,
      minIndent: minIndent,
      forceInline: forceInline,
      onParseComment: comments.add,
    )) {
      break;
    }
  } while (scanner.canChunkMore);

  return terminateFlowCollection(scanner, map, mappingEnd);
}
